function Get-ProcessTrace {
<#
.SYNOPSIS
Walks thread stacks of specified process(es) to help identify dll injection.

.DESCRIPTION
This commandlet uses Windows Remote Management to walk thread stacks of specified process(es).

.PARAMETER TargetList 
Specify a list of hosts to retrieve data from.

.PARAMETER ComputerName 
Specifies one computer to retrieve data from.

.PARAMETER ConfirmTargets
Verify that targets exist in the network before attempting to retrieve data.

.PARAMETER Name 
Specify name of process whose threads should be walked.

.PARAMETER Id 
Specify process Id of process whose threads should be walked.

.PARAMETER Timeout 
Specify timeout length, defaults to 3 seconds.

.PARAMETER CSV 
Specify path to output file, output is formatted as comma separated values.

.PARAMETER TXT 
Specify path to output file, output formatted as text.

.EXAMPLE
The following example gets a list of computers from the pipeline and sends output to a csv file.

PS C:\> $Targs = New-TargetList -Cidr 10.10.20.0/24
PS C:\> Get-ProcessTrace -TargetList $Targs -Name svchost -CSV C:\pathto\output.csv

.EXAMPLE
The following example specifies a computer and writes output to the console.

PS C:\> Get-ProcessTrace -TargetList Server01 -Name svchost

.NOTES
Version: 0.1
Author : RBOT

.INPUTS

.OUTPUTS

.LINK
#>
[CmdLetBinding(SupportsShouldProcess = $false)]
    Param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$TargetList,

        [Parameter()]
        [Switch]$ConfirmTargets,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Int]$ThrottleLimit = 10,

        [Parameter(ParameterSetName = "Name")]
        [ValidateNotNullOrEmpty()]
        [String]$Name = "",

        [Parameter(ParameterSetName = "Id")]
        [ValidateNotNullOrEmpty()]
        [Int]$Id = -1,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$CSV,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$TXT
    )
        
    if($PSBoundParameters['CSV']) { $OutputFilePath = (Resolve-Path (Split-Path $CSV -Parent)).Path + '\' + (Split-Path $CSV -Leaf) }
    elseif($PSBoundParameters['TXT']) { $OutputFilePath = (Resolve-Path (Split-Path $TXT -Parent)).Path + '\' + (Split-Path $TXT -Leaf) }

    $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
    $ErrorFileHosts,$ErrorFileVerbose = Set-ErrorFiles -ModuleName Get-ProcessTrace
        
    $Global:Error.Clear()
    $RemoteScriptBlock = {
        Param (
            [Parameter(Position = 0)]
            [String]$Name, 

            [Parameter(Position = 1)]
            [Int]$Id
        )
        $Domain = [AppDomain]::CurrentDomain
        $DynAssembly = New-Object System.Reflection.AssemblyName('PowerWalker')
        $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
        $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
        $ConstructorInfo = [Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]

        #region STRUCTS
            
            #region ENUM ProcessorArch
            $TypeBuilder = $ModuleBuilder.DefineEnum('ProcessorArch', 'Public', [UInt16])
            [void]$TypeBuilder.DefineLiteral('PROCESSOR_ARCHITECTURE_INTEL', [UInt16] 0)
            [void]$TypeBuilder.DefineLiteral('PROCESSOR_ARCHITECTURE_MIPS', [UInt16] 0x01)
            [void]$TypeBuilder.DefineLiteral('PROCESSOR_ARCHITECTURE_ALPHA', [UInt16] 0x02)
            [void]$TypeBuilder.DefineLiteral('PROCESSOR_ARCHITECTURE_PPC', [UInt16] 0x03)
            [void]$TypeBuilder.DefineLiteral('PROCESSOR_ARCHITECTURE_SHX', [UInt16] 0x04)
            [void]$TypeBuilder.DefineLiteral('PROCESSOR_ARCHITECTURE_ARM', [UInt16] 0x05)
            [void]$TypeBuilder.DefineLiteral('PROCESSOR_ARCHITECTURE_IA64', [UInt16] 0x06)
            [void]$TypeBuilder.DefineLiteral('PROCESSOR_ARCHITECTURE_ALPHA64', [UInt16] 0x07)
            [void]$TypeBuilder.DefineLiteral('PROCESSOR_ARCHITECTURE_AMD64', [UInt16] 0x09)
            [void]$TypeBuilder.DefineLiteral('PROCESSOR_ARCHITECTURE_UNKNOWN', [UInt16] 0xFFFF)
            $Global:ProcessorArch = $TypeBuilder.CreateType()
            #endregion ENUM ProcessorArch
            
            #region SYSTEM_INFO
            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
            $TypeBuilder = $ModuleBuilder.DefineType('SYSTEM_INFO', $Attributes, [ValueType])
            [void]$TypeBuilder.DefineField('ProcessorArchitecture', $ProcessorArch, 'Public')
            [void]$TypeBuilder.DefineField('Reserved', [Int16], 'Public')
            [void]$TypeBuilder.DefineField('PageSize', [Int32], 'Public')
            [void]$TypeBuilder.DefineField('MinimumApplicationAddress', [IntPtr], 'Public')
            [void]$TypeBuilder.DefineField('MaximumApplicationAddress', [IntPtr], 'Public')
            [void]$TypeBuilder.DefineField('ActiveProcessorMask', [IntPtr], 'Public')
            [void]$TypeBuilder.DefineField('NumberOfProcessors', [Int32], 'Public')
            [void]$TypeBuilder.DefineField('ProcessorType', [Int32], 'Public')
            [void]$TypeBuilder.DefineField('AllocationGranularity', [Int32], 'Public')
            [void]$TypeBuilder.DefineField('ProcessorLevel', [Int16], 'Public')
            [void]$TypeBuilder.DefineField('ProcessorRevision', [Int16], 'Public')
            $Global:SYSTEM_INFO = $TypeBuilder.CreateType()
            #endregion SYSTEM_INFO

            #region MODULE_INFO
            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
            $TypeBuilder = $ModuleBuilder.DefineType('MODULE_INFO', $Attributes, [ValueType], 12)
            [void]$TypeBuilder.DefineField('lpBaseOfDll', [IntPtr], 'Public')
            [void]$TypeBuilder.DefineField('SizeOfImage', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('EntryPoint', [IntPtr], 'Public')
            $Global:MODULE_INFO = $TypeBuilder.CreateType()
            #endregion MODULE_INFO

            #region KDHELP
            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
            $TypeBuilder = $ModuleBuilder.DefineType('KDHELP', $Attributes, [ValueType])
            [void]$TypeBuilder.DefineField('Thread', [UInt64], 'Public')
            [void]$TypeBuilder.DefineField('ThCallbackStack', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('ThCallbackBStore', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('NextCallback', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('FramePointer', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('KiCallUserMode', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('KeUserCallbackDispatcher', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('SystemRangeStart', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('KiUserExceptionDispatcher', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('StackBase', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('StackLimit', [UInt32], 'Public')
            $ReservedField = $TypeBuilder.DefineField('Reserved', [UInt64[]], 'Public')
            $FieldArray = @([Runtime.InteropServices.MarshalAsAttribute].GetField('SizeConst'))
            $ConstructorValue = [Runtime.InteropServices.UnmanagedType]::ByValArray
            $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 5))
            [void]$ReservedField.SetCustomAttribute($AttribBuilder)
            $KDHELP = $TypeBuilder.CreateType()
            #endregion KDHELP

            #region ADDRESS64
            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
            $TypeBuilder = $ModuleBuilder.DefineType('ADDRESS64', $Attributes, [ValueType])
            [void]$TypeBuilder.DefineField('Offset', [UInt64], 'Public')
            [void]$TypeBuilder.DefineField('Segment', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Mode', [UInt32], 'Public')
            $Global:ADDRESS64 = $TypeBuilder.CreateType()
            #endregion ADDRESS64

            #region STACKFRAME64
            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
            $TypeBuilder = $ModuleBuilder.DefineType('STACKFRAME64', $Attributes, [ValueType])
            [void]$TypeBuilder.DefineField('AddrPC', $ADDRESS64, 'Public')
            [void]$TypeBuilder.DefineField('AddrReturn', $ADDRESS64, 'Public')
            [void]$TypeBuilder.DefineField('AddrFrame', $ADDRESS64, 'Public')
            [void]$TypeBuilder.DefineField('AddrStack', $ADDRESS64, 'Public')
            [void]$TypeBuilder.DefineField('AddrBStore', $ADDRESS64, 'Public')
            [void]$TypeBuilder.DefineField('FuncTableEntry', [IntPtr], 'Public')
            [void]$TypeBuilder.DefineField('Offset', [UInt64], 'Public')
            $ParamsField = $TypeBuilder.DefineField('Params', [UInt64[]], 'Public')
            $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 4))
            [void]$ParamsField.SetCustomAttribute($AttribBuilder)
            [void]$TypeBuilder.DefineField('Far', [Bool], 'Public')
            [void]$TypeBuilder.DefineField('Virtual', [Bool], 'Public')
            $ReservedField = $TypeBuilder.DefineField('Reserved', [UInt64[]], 'Public')
            $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 3))
            [void]$ReservedField.SetCustomAttribute($AttribBuilder)
            [void]$TypeBuilder.DefineField('KdHelp', $KDHELP, 'Public')
            $Global:STACKFRAME64 = $TypeBuilder.CreateType()
            #endregion STACKFRAME64

            #region IMAGEHLP_SYMBOLW64
            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
            $TypeBuilder = $ModuleBuilder.DefineType('IMAGEHLP_SYMBOLW64', $Attributes, [ValueType])
            [void]$TypeBuilder.DefineField('SizeOfStruct', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Address', [UInt64], 'Public')
            [void]$TypeBuilder.DefineField('Size', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Flags', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('MaxNameLength', [UInt32], 'Public')
            $NameField = $TypeBuilder.DefineField('Name', [Char[]], 'Public')
            $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 33))
            [void]$NameField.SetCustomAttribute($AttribBuilder)
            $Global:IMAGEHLP_SYMBOLW64 = $TypeBuilder.CreateType()
            #endregion IMAGEHLP_SYMBOLW64
    
            #region FLOAT128
            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
            $TypeBuilder = $ModuleBuilder.DefineType('FLOAT128', $Attributes, [ValueType])
            [void]$TypeBuilder.DefineField('LowPart', [Int64], 'Public')
            [void]$TypeBuilder.DefineField('HighPart', [Int64], 'Public')
            $FLOAT128 = $TypeBuilder.CreateType()
            #endregion FLOAT128

            #region FLOATING_SAVE_AREA
            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
            $TypeBuilder = $ModuleBuilder.DefineType('FLOATING_SAVE_AREA', $Attributes, [ValueType])
            [void]$TypeBuilder.DefineField('ControlWord', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('StatusWord', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('TagWord', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('ErrorOffset', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('ErrorSelector', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('DataOffset', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('DataSelector', [UInt32], 'Public')
            $RegisterAreaField = $TypeBuilder.DefineField('RegisterArea', [Byte[]], 'Public')
            $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 80))
            [void]$RegisterAreaField.SetCustomAttribute($AttribBuilder)
            [void]$TypeBuilder.DefineField('Cr0NpxState', [UInt32], 'Public')
            $FLOATING_SAVE_AREA = $TypeBuilder.CreateType()
            #endregion FLOATING_SAVE_AREA

            #region X86_CONTEXT
            $Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
            $TypeBuilder = $ModuleBuilder.DefineType('X86_CONTEXT', $Attributes, [ValueType])
            [void]$TypeBuilder.DefineField('ContextFlags', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Dr0', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Dr1', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Dr2', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Dr3', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Dr6', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Dr7', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('FloatSave', $FLOATING_SAVE_AREA, 'Public')
            [void]$TypeBuilder.DefineField('SegGs', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('SegFs', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('SegEs', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('SegDs', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Edi', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Esi', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Ebx', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Edx', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Ecx', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Eax', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Ebp', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Eip', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('SegCs', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('EFlags', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('Esp', [UInt32], 'Public')
            [void]$TypeBuilder.DefineField('SegSs', [UInt32], 'Public')
            $ExtendedRegistersField = $TypeBuilder.DefineField('ExtendedRegisters', [Byte[]], 'Public')
            $AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 512))
            [void]$ExtendedRegistersField.SetCustomAttribute($AttribBuilder)
            $Global:X86_CONTEXT = $TypeBuilder.CreateType()
            #endregion X86_CONTEXT

            #region AMD64_CONTEXT
            $Attributes = 'AutoLayout, AnsiClass, Class, Public, ExplicitLayout, Sealed, BeforeFieldInit'
            $TypeBuilder = $ModuleBuilder.DefineType('AMD64_CONTEXT', $Attributes, [ValueType])	    
            ($TypeBuilder.DefineField('P1Home', [UInt64], 'Public')).SetOffset(0x0)
            ($TypeBuilder.DefineField('P2Home', [UInt64], 'Public')).SetOffset(0x8)
            ($TypeBuilder.DefineField('P3Home', [UInt64], 'Public')).SetOffset(0x10)
            ($TypeBuilder.DefineField('P4Home', [UInt64], 'Public')).SetOffset(0x18)
            ($TypeBuilder.DefineField('P5Home', [UInt64], 'Public')).SetOffset(0x20)
            ($TypeBuilder.DefineField('P6Home', [UInt64], 'Public')).SetOffset(0x28)
            ($TypeBuilder.DefineField('ContextFlags', [UInt32], 'Public')).SetOffset(0x30)
            ($TypeBuilder.DefineField('MxCsr', [UInt32], 'Public')).SetOffset(0x34)
            ($TypeBuilder.DefineField('SegCs', [UInt16], 'Public')).SetOffset(0x38)
            ($TypeBuilder.DefineField('SegDs', [UInt16], 'Public')).SetOffset(0x3a)
            ($TypeBuilder.DefineField('SegEs', [UInt16], 'Public')).SetOffset(0x3c)
            ($TypeBuilder.DefineField('SegFs', [UInt16], 'Public')).SetOffset(0x3e)
            ($TypeBuilder.DefineField('SegGs', [UInt16], 'Public')).SetOffset(0x40)
            ($TypeBuilder.DefineField('SegSs', [UInt16], 'Public')).SetOffset(0x42)
            ($TypeBuilder.DefineField('EFlags', [UInt32], 'Public')).SetOffset(0x44)
            ($TypeBuilder.DefineField('Dr0', [UInt64], 'Public')).SetOffset(0x48)
            ($TypeBuilder.DefineField('Dr1', [UInt64], 'Public')).SetOffset(0x50)
            ($TypeBuilder.DefineField('Dr2', [UInt64], 'Public')).SetOffset(0x58)
            ($TypeBuilder.DefineField('Dr3', [UInt64], 'Public')).SetOffset(0x60)
            ($TypeBuilder.DefineField('Dr6', [UInt64], 'Public')).SetOffset(0x68)
            ($TypeBuilder.DefineField('Dr7', [UInt64], 'Public')).SetOffset(0x70)
            ($TypeBuilder.DefineField('Rax', [UInt64], 'Public')).SetOffset(0x78)
            ($TypeBuilder.DefineField('Rcx', [UInt64], 'Public')).SetOffset(0x80)
            ($TypeBuilder.DefineField('Rdx', [UInt64], 'Public')).SetOffset(0x88)
            ($TypeBuilder.DefineField('Rbx', [UInt64], 'Public')).SetOffset(0x90)
            ($TypeBuilder.DefineField('Rsp', [UInt64], 'Public')).SetOffset(0x98)
            ($TypeBuilder.DefineField('Rbp', [UInt64], 'Public')).SetOffset(0xa0)
            ($TypeBuilder.DefineField('Rsi', [UInt64], 'Public')).SetOffset(0xa8)
            ($TypeBuilder.DefineField('Rdi', [UInt64], 'Public')).SetOffset(0xb0)
            ($TypeBuilder.DefineField('R8', [UInt64], 'Public')).SetOffset(0xa8)
            ($TypeBuilder.DefineField('R9', [UInt64], 'Public')).SetOffset(0xc0)
            ($TypeBuilder.DefineField('R10', [UInt64], 'Public')).SetOffset(0xc8)
            ($TypeBuilder.DefineField('R11', [UInt64], 'Public')).SetOffset(0xd0)
            ($TypeBuilder.DefineField('R12', [UInt64], 'Public')).SetOffset(0xd8)
            ($TypeBuilder.DefineField('R13', [UInt64], 'Public')).SetOffset(0xe0)
            ($TypeBuilder.DefineField('R14', [UInt64], 'Public')).SetOffset(0xe8)
            ($TypeBuilder.DefineField('R15', [UInt64], 'Public')).SetOffset(0xf0)
            ($TypeBuilder.DefineField('Rip', [UInt64], 'Public')).SetOffset(0xf8)               
            ($TypeBuilder.DefineField('FltSave', [UInt64], 'Public')).SetOffset(0x100)
            ($TypeBuilder.DefineField('Legacy', [UInt64], 'Public')).SetOffset(0x120)
            ($TypeBuilder.DefineField('Xmm0', [UInt64], 'Public')).SetOffset(0x1a0)
            ($TypeBuilder.DefineField('Xmm1', [UInt64], 'Public')).SetOffset(0x1b0)
            ($TypeBuilder.DefineField('Xmm2', [UInt64], 'Public')).SetOffset(0x1c0)
            ($TypeBuilder.DefineField('Xmm3', [UInt64], 'Public')).SetOffset(0x1d0)
            ($TypeBuilder.DefineField('Xmm4', [UInt64], 'Public')).SetOffset(0x1e0)
            ($TypeBuilder.DefineField('Xmm5', [UInt64], 'Public')).SetOffset(0x1f0)
            ($TypeBuilder.DefineField('Xmm6', [UInt64], 'Public')).SetOffset(0x200)
            ($TypeBuilder.DefineField('Xmm7', [UInt64], 'Public')).SetOffset(0x210)
            ($TypeBuilder.DefineField('Xmm8', [UInt64], 'Public')).SetOffset(0x220)
            ($TypeBuilder.DefineField('Xmm9', [UInt64], 'Public')).SetOffset(0x230)
            ($TypeBuilder.DefineField('Xmm10', [UInt64], 'Public')).SetOffset(0x240)
            ($TypeBuilder.DefineField('Xmm11', [UInt64], 'Public')).SetOffset(0x250)
            ($TypeBuilder.DefineField('Xmm12', [UInt64], 'Public')).SetOffset(0x260)
            ($TypeBuilder.DefineField('Xmm13', [UInt64], 'Public')).SetOffset(0x270)
            ($TypeBuilder.DefineField('Xmm14', [UInt64], 'Public')).SetOffset(0x280)
            ($TypeBuilder.DefineField('Xmm15', [UInt64], 'Public')).SetOffset(0x290)
            ($TypeBuilder.DefineField('VectorRegister', [UInt64], 'Public')).SetOffset(0x300)
            ($TypeBuilder.DefineField('VectorControl', [UInt64], 'Public')).SetOffset(0x4a0)
            ($TypeBuilder.DefineField('DebugControl', [UInt64], 'Public')).SetOffset(0x4a8)
            ($TypeBuilder.DefineField('LastBranchToRip', [UInt64], 'Public')).SetOffset(0x4b0)
            ($TypeBuilder.DefineField('LastBranchFromRip', [UInt64], 'Public')).SetOffset(0x4b8)
            ($TypeBuilder.DefineField('LastExceptionToRip', [UInt64], 'Public')).SetOffset(0x4c0)
            ($TypeBuilder.DefineField('LastExceptionFromRip', [UInt64], 'Public')).SetOffset(0x4c8)
            $Global:AMD64_CONTEXT = $TypeBuilder.CreateType()
            #endregion AMD64_CONTEXT

            #region IA64_CONTEXT
            $Attributes = 'AutoLayout, AnsiClass, Class, Public, ExplicitLayout, Sealed, BeforeFieldInit'
            $TypeBuilder = $ModuleBuilder.DefineType('IA64_CONTEXT', $Attributes, [ValueType])    
            ($TypeBuilder.DefineField('ContextFlags', [UInt64], 'Public')).SetOffset(0x0)
            ($TypeBuilder.DefineField('DbI0', [UInt64], 'Public')).SetOffset(0x010)
            ($TypeBuilder.DefineField('DbI1', [UInt64], 'Public')).SetOffset(0x018)
            ($TypeBuilder.DefineField('DbI2', [UInt64], 'Public')).SetOffset(0x020)
            ($TypeBuilder.DefineField('DbI3', [UInt64], 'Public')).SetOffset(0x028)
            ($TypeBuilder.DefineField('DbI4', [UInt64], 'Public')).SetOffset(0x030)
            ($TypeBuilder.DefineField('DbI5', [UInt64], 'Public')).SetOffset(0x038)
            ($TypeBuilder.DefineField('DbI6', [UInt64], 'Public')).SetOffset(0x040)
            ($TypeBuilder.DefineField('DbI7', [UInt64], 'Public')).SetOffset(0x048)
            ($TypeBuilder.DefineField('DbD0', [UInt64], 'Public')).SetOffset(0x050)
            ($TypeBuilder.DefineField('DbD1', [UInt64], 'Public')).SetOffset(0x058)
            ($TypeBuilder.DefineField('DbD2', [UInt64], 'Public')).SetOffset(0x060)
            ($TypeBuilder.DefineField('DbD3', [UInt64], 'Public')).SetOffset(0x068)
            ($TypeBuilder.DefineField('DbD4', [UInt64], 'Public')).SetOffset(0x070)
            ($TypeBuilder.DefineField('DbD5', [UInt64], 'Public')).SetOffset(0x078)
            ($TypeBuilder.DefineField('DbD6', [UInt64], 'Public')).SetOffset(0x080)
            ($TypeBuilder.DefineField('DbD7', [UInt64], 'Public')).SetOffset(0x088)
            ($TypeBuilder.DefineField('FltS0', $FLOAT128, 'Public')).SetOffset(0x090) 
            ($TypeBuilder.DefineField('FltS1', $FLOAT128, 'Public')).SetOffset(0x0a0)
            ($TypeBuilder.DefineField('FltS2', $FLOAT128, 'Public')).SetOffset(0x0b0) 
            ($TypeBuilder.DefineField('FltS3', $FLOAT128, 'Public')).SetOffset(0x0c0)
            ($TypeBuilder.DefineField('FltT0', $FLOAT128, 'Public')).SetOffset(0x0d0) 
            ($TypeBuilder.DefineField('FltT1', $FLOAT128, 'Public')).SetOffset(0x0e0) 
            ($TypeBuilder.DefineField('FltT2', $FLOAT128, 'Public')).SetOffset(0x0f0) 
            ($TypeBuilder.DefineField('FltT3', $FLOAT128, 'Public')).SetOffset(0x100) 
            ($TypeBuilder.DefineField('FltT4', $FLOAT128, 'Public')).SetOffset(0x110) 
            ($TypeBuilder.DefineField('FltT5', $FLOAT128, 'Public')).SetOffset(0x120) 
            ($TypeBuilder.DefineField('FltT6', $FLOAT128, 'Public')).SetOffset(0x130) 
            ($TypeBuilder.DefineField('FltT7', $FLOAT128, 'Public')).SetOffset(0x140)
            ($TypeBuilder.DefineField('FltT8', $FLOAT128, 'Public')).SetOffset(0x150)
            ($TypeBuilder.DefineField('FltT9', $FLOAT128, 'Public')).SetOffset(0x160)
            ($TypeBuilder.DefineField('FltS4', $FLOAT128, 'Public')).SetOffset(0x170) 
            ($TypeBuilder.DefineField('FltS5', $FLOAT128, 'Public')).SetOffset(0x180) 
            ($TypeBuilder.DefineField('FltS6', $FLOAT128, 'Public')).SetOffset(0x190) 
            ($TypeBuilder.DefineField('FltS7', $FLOAT128, 'Public')).SetOffset(0x1a0) 
            ($TypeBuilder.DefineField('FltS8', $FLOAT128, 'Public')).SetOffset(0x1b0) 
            ($TypeBuilder.DefineField('FltS9', $FLOAT128, 'Public')).SetOffset(0x1c0) 
            ($TypeBuilder.DefineField('FltS10', $FLOAT128, 'Public')).SetOffset(0x1d0) 
            ($TypeBuilder.DefineField('FltS11', $FLOAT128, 'Public')).SetOffset(0x1e0) 
            ($TypeBuilder.DefineField('FltS12', $FLOAT128, 'Public')).SetOffset(0x1f0) 
            ($TypeBuilder.DefineField('FltS13', $FLOAT128, 'Public')).SetOffset(0x200) 
            ($TypeBuilder.DefineField('FltS14', $FLOAT128, 'Public')).SetOffset(0x210) 
            ($TypeBuilder.DefineField('FltS15', $FLOAT128, 'Public')).SetOffset(0x220) 
            ($TypeBuilder.DefineField('FltS16', $FLOAT128, 'Public')).SetOffset(0x230)
            ($TypeBuilder.DefineField('FltS17', $FLOAT128, 'Public')).SetOffset(0x240)
            ($TypeBuilder.DefineField('FltS18', $FLOAT128, 'Public')).SetOffset(0x250) 
            ($TypeBuilder.DefineField('FltS19', $FLOAT128, 'Public')).SetOffset(0x260) 
            ($TypeBuilder.DefineField('FltF32', $FLOAT128, 'Public')).SetOffset(0x270) 
            ($TypeBuilder.DefineField('FltF33', $FLOAT128, 'Public')).SetOffset(0x280) 
            ($TypeBuilder.DefineField('FltF34', $FLOAT128, 'Public')).SetOffset(0x290) 
            ($TypeBuilder.DefineField('FltF35', $FLOAT128, 'Public')).SetOffset(0x2a0) 
            ($TypeBuilder.DefineField('FltF36', $FLOAT128, 'Public')).SetOffset(0x2b0) 
            ($TypeBuilder.DefineField('FltF37', $FLOAT128, 'Public')).SetOffset(0x2c0) 
            ($TypeBuilder.DefineField('FltF38', $FLOAT128, 'Public')).SetOffset(0x2d0) 
            ($TypeBuilder.DefineField('FltF39', $FLOAT128, 'Public')).SetOffset(0x2e0)
            ($TypeBuilder.DefineField('FltF40', $FLOAT128, 'Public')).SetOffset(0x2f0) 
            ($TypeBuilder.DefineField('FltF41', $FLOAT128, 'Public')).SetOffset(0x300) 
            ($TypeBuilder.DefineField('FltF42', $FLOAT128, 'Public')).SetOffset(0x310) 
            ($TypeBuilder.DefineField('FltF43', $FLOAT128, 'Public')).SetOffset(0x320) 
            ($TypeBuilder.DefineField('FltF44', $FLOAT128, 'Public')).SetOffset(0x330) 
            ($TypeBuilder.DefineField('FltF45', $FLOAT128, 'Public')).SetOffset(0x340) 
            ($TypeBuilder.DefineField('FltF46', $FLOAT128, 'Public')).SetOffset(0x350) 
            ($TypeBuilder.DefineField('FltF47', $FLOAT128, 'Public')).SetOffset(0x360) 
            ($TypeBuilder.DefineField('FltF48', $FLOAT128, 'Public')).SetOffset(0x370) 
            ($TypeBuilder.DefineField('FltF49', $FLOAT128, 'Public')).SetOffset(0x380) 
            ($TypeBuilder.DefineField('FltF50', $FLOAT128, 'Public')).SetOffset(0x390) 
            ($TypeBuilder.DefineField('FltF51', $FLOAT128, 'Public')).SetOffset(0x3a0) 
            ($TypeBuilder.DefineField('FltF52', $FLOAT128, 'Public')).SetOffset(0x3b0) 
            ($TypeBuilder.DefineField('FltF53', $FLOAT128, 'Public')).SetOffset(0x3c0) 
            ($TypeBuilder.DefineField('FltF54', $FLOAT128, 'Public')).SetOffset(0x3d0) 
            ($TypeBuilder.DefineField('FltF55', $FLOAT128, 'Public')).SetOffset(0x3e0) 
            ($TypeBuilder.DefineField('FltF56', $FLOAT128, 'Public')).SetOffset(0x3f0) 
            ($TypeBuilder.DefineField('FltF57', $FLOAT128, 'Public')).SetOffset(0x400) 
            ($TypeBuilder.DefineField('FltF58', $FLOAT128, 'Public')).SetOffset(0x410) 
            ($TypeBuilder.DefineField('FltF59', $FLOAT128, 'Public')).SetOffset(0x420) 
            ($TypeBuilder.DefineField('FltF60', $FLOAT128, 'Public')).SetOffset(0x430) 
            ($TypeBuilder.DefineField('FltF61', $FLOAT128, 'Public')).SetOffset(0x440) 
            ($TypeBuilder.DefineField('FltF62', $FLOAT128, 'Public')).SetOffset(0x450) 
            ($TypeBuilder.DefineField('FltF63', $FLOAT128, 'Public')).SetOffset(0x460) 
            ($TypeBuilder.DefineField('FltF64', $FLOAT128, 'Public')).SetOffset(0x470) 
            ($TypeBuilder.DefineField('FltF65', $FLOAT128, 'Public')).SetOffset(0x480) 
            ($TypeBuilder.DefineField('FltF66', $FLOAT128, 'Public')).SetOffset(0x490) 
            ($TypeBuilder.DefineField('FltF67', $FLOAT128, 'Public')).SetOffset(0x4a0) 
            ($TypeBuilder.DefineField('FltF68', $FLOAT128, 'Public')).SetOffset(0x4b0) 
            ($TypeBuilder.DefineField('FltF69', $FLOAT128, 'Public')).SetOffset(0x4c0) 
            ($TypeBuilder.DefineField('FltF70', $FLOAT128, 'Public')).SetOffset(0x4d0) 
            ($TypeBuilder.DefineField('FltF71', $FLOAT128, 'Public')).SetOffset(0x4e0) 
            ($TypeBuilder.DefineField('FltF72', $FLOAT128, 'Public')).SetOffset(0x4f0) 
            ($TypeBuilder.DefineField('FltF73', $FLOAT128, 'Public')).SetOffset(0x500) 
            ($TypeBuilder.DefineField('FltF74', $FLOAT128, 'Public')).SetOffset(0x510) 
            ($TypeBuilder.DefineField('FltF75', $FLOAT128, 'Public')).SetOffset(0x520) 
            ($TypeBuilder.DefineField('FltF76', $FLOAT128, 'Public')).SetOffset(0x530) 
            ($TypeBuilder.DefineField('FltF77', $FLOAT128, 'Public')).SetOffset(0x540) 
            ($TypeBuilder.DefineField('FltF78', $FLOAT128, 'Public')).SetOffset(0x550) 
            ($TypeBuilder.DefineField('FltF79', $FLOAT128, 'Public')).SetOffset(0x560) 
            ($TypeBuilder.DefineField('FltF80', $FLOAT128, 'Public')).SetOffset(0x570) 
            ($TypeBuilder.DefineField('FltF81', $FLOAT128, 'Public')).SetOffset(0x580) 
            ($TypeBuilder.DefineField('FltF82', $FLOAT128, 'Public')).SetOffset(0x590) 
            ($TypeBuilder.DefineField('FltF83', $FLOAT128, 'Public')).SetOffset(0x5a0) 
            ($TypeBuilder.DefineField('FltF84', $FLOAT128, 'Public')).SetOffset(0x5b0) 
            ($TypeBuilder.DefineField('FltF85', $FLOAT128, 'Public')).SetOffset(0x5c0) 
            ($TypeBuilder.DefineField('FltF86', $FLOAT128, 'Public')).SetOffset(0x5d0) 
            ($TypeBuilder.DefineField('FltF87', $FLOAT128, 'Public')).SetOffset(0x5e0) 
            ($TypeBuilder.DefineField('FltF88', $FLOAT128, 'Public')).SetOffset(0x5f0) 
            ($TypeBuilder.DefineField('FltF89', $FLOAT128, 'Public')).SetOffset(0x600) 
            ($TypeBuilder.DefineField('FltF90', $FLOAT128, 'Public')).SetOffset(0x610)
            ($TypeBuilder.DefineField('FltF91', $FLOAT128, 'Public')).SetOffset(0x620) 
            ($TypeBuilder.DefineField('FltF92', $FLOAT128, 'Public')).SetOffset(0x630) 
            ($TypeBuilder.DefineField('FltF93', $FLOAT128, 'Public')).SetOffset(0x640) 
            ($TypeBuilder.DefineField('FltF94', $FLOAT128, 'Public')).SetOffset(0x650) 
            ($TypeBuilder.DefineField('FltF95', $FLOAT128, 'Public')).SetOffset(0x660) 
            ($TypeBuilder.DefineField('FltF96', $FLOAT128, 'Public')).SetOffset(0x670) 
            ($TypeBuilder.DefineField('FltF97', $FLOAT128, 'Public')).SetOffset(0x680) 
            ($TypeBuilder.DefineField('FltF98', $FLOAT128, 'Public')).SetOffset(0x690) 
            ($TypeBuilder.DefineField('FltF99', $FLOAT128, 'Public')).SetOffset(0x6a0) 
            ($TypeBuilder.DefineField('FltF100', $FLOAT128, 'Public')).SetOffset(0x6b0) 
            ($TypeBuilder.DefineField('FltF101', $FLOAT128, 'Public')).SetOffset(0x6c0) 
            ($TypeBuilder.DefineField('FltF102', $FLOAT128, 'Public')).SetOffset(0x6d0) 
            ($TypeBuilder.DefineField('FltF103', $FLOAT128, 'Public')).SetOffset(0x6e0) 
            ($TypeBuilder.DefineField('FltF104', $FLOAT128, 'Public')).SetOffset(0x6f0) 
            ($TypeBuilder.DefineField('FltF105', $FLOAT128, 'Public')).SetOffset(0x700) 
            ($TypeBuilder.DefineField('FltF106', $FLOAT128, 'Public')).SetOffset(0x710) 
            ($TypeBuilder.DefineField('FltF107', $FLOAT128, 'Public')).SetOffset(0x720) 
            ($TypeBuilder.DefineField('FltF108', $FLOAT128, 'Public')).SetOffset(0x730)
            ($TypeBuilder.DefineField('FltF109', $FLOAT128, 'Public')).SetOffset(0x740) 
            ($TypeBuilder.DefineField('FltF110', $FLOAT128, 'Public')).SetOffset(0x750) 
            ($TypeBuilder.DefineField('FltF111', $FLOAT128, 'Public')).SetOffset(0x760) 
            ($TypeBuilder.DefineField('FltF112', $FLOAT128, 'Public')).SetOffset(0x770) 
            ($TypeBuilder.DefineField('FltF113', $FLOAT128, 'Public')).SetOffset(0x780) 
            ($TypeBuilder.DefineField('FltF114', $FLOAT128, 'Public')).SetOffset(0x790) 
            ($TypeBuilder.DefineField('FltF115', $FLOAT128, 'Public')).SetOffset(0x7a0) 
            ($TypeBuilder.DefineField('FltF116', $FLOAT128, 'Public')).SetOffset(0x7b0) 
            ($TypeBuilder.DefineField('FltF117', $FLOAT128, 'Public')).SetOffset(0x7c0) 
            ($TypeBuilder.DefineField('FltF118', $FLOAT128, 'Public')).SetOffset(0x7d0) 
            ($TypeBuilder.DefineField('FltF119', $FLOAT128, 'Public')).SetOffset(0x7e0) 
            ($TypeBuilder.DefineField('FltF120', $FLOAT128, 'Public')).SetOffset(0x7f0) 
            ($TypeBuilder.DefineField('FltF121', $FLOAT128, 'Public')).SetOffset(0x800) 
            ($TypeBuilder.DefineField('FltF122', $FLOAT128, 'Public')).SetOffset(0x810) 
            ($TypeBuilder.DefineField('FltF123', $FLOAT128, 'Public')).SetOffset(0x820) 
            ($TypeBuilder.DefineField('FltF124', $FLOAT128, 'Public')).SetOffset(0x830) 
            ($TypeBuilder.DefineField('FltF125', $FLOAT128, 'Public')).SetOffset(0x840) 
            ($TypeBuilder.DefineField('FltF126', $FLOAT128, 'Public')).SetOffset(0x850) 
            ($TypeBuilder.DefineField('FltF127', $FLOAT128, 'Public')).SetOffset(0x860) 
            ($TypeBuilder.DefineField('StFPSR', [UInt64], 'Public')).SetOffset(0x870) 
            ($TypeBuilder.DefineField('IntGp', [UInt64], 'Public')).SetOffset(0x870) 
            ($TypeBuilder.DefineField('IntT0', [UInt64], 'Public')).SetOffset(0x880)  
            ($TypeBuilder.DefineField('IntT1', [UInt64], 'Public')).SetOffset(0x888)  
            ($TypeBuilder.DefineField('IntS0', [UInt64], 'Public')).SetOffset(0x890)  
            ($TypeBuilder.DefineField('IntS1', [UInt64], 'Public')).SetOffset(0x898) 
            ($TypeBuilder.DefineField('IntS2', [UInt64], 'Public')).SetOffset(0x8a0) 
            ($TypeBuilder.DefineField('IntS3', [UInt64], 'Public')).SetOffset(0x8a8) 
            ($TypeBuilder.DefineField('IntV0', [UInt64], 'Public')).SetOffset(0x8b0)  
            ($TypeBuilder.DefineField('IntT2', [UInt64], 'Public')).SetOffset(0x8b8)  
            ($TypeBuilder.DefineField('IntT3', [UInt64], 'Public')).SetOffset(0x8c0) 
            ($TypeBuilder.DefineField('IntT4', [UInt64], 'Public')).SetOffset(0x8c8) 
            ($TypeBuilder.DefineField('IntSp', [UInt64], 'Public')).SetOffset(0x8d0)   
            ($TypeBuilder.DefineField('IntTeb', [UInt64], 'Public')).SetOffset(0x8d8)  
            ($TypeBuilder.DefineField('IntT5', [UInt64], 'Public')).SetOffset(0x8e0)  
            ($TypeBuilder.DefineField('IntT6', [UInt64], 'Public')).SetOffset(0x8e8) 
            ($TypeBuilder.DefineField('IntT7', [UInt64], 'Public')).SetOffset(0x8f0) 
            ($TypeBuilder.DefineField('IntT8', [UInt64], 'Public')).SetOffset(0x8f8) 
            ($TypeBuilder.DefineField('IntT9', [UInt64], 'Public')).SetOffset(0x900) 
            ($TypeBuilder.DefineField('IntT10', [UInt64], 'Public')).SetOffset(0x908) 
            ($TypeBuilder.DefineField('IntT11', [UInt64], 'Public')).SetOffset(0x910) 
            ($TypeBuilder.DefineField('IntT12', [UInt64], 'Public')).SetOffset(0x918) 
            ($TypeBuilder.DefineField('IntT13', [UInt64], 'Public')).SetOffset(0x920) 
            ($TypeBuilder.DefineField('IntT14', [UInt64], 'Public')).SetOffset(0x928) 
            ($TypeBuilder.DefineField('IntT15', [UInt64], 'Public')).SetOffset(0x930) 
            ($TypeBuilder.DefineField('IntT16', [UInt64], 'Public')).SetOffset(0x938) 
            ($TypeBuilder.DefineField('IntT17', [UInt64], 'Public')).SetOffset(0x940) 
            ($TypeBuilder.DefineField('IntT18', [UInt64], 'Public')).SetOffset(0x948) 
            ($TypeBuilder.DefineField('IntT19', [UInt64], 'Public')).SetOffset(0x950) 
            ($TypeBuilder.DefineField('IntT20', [UInt64], 'Public')).SetOffset(0x958)
            ($TypeBuilder.DefineField('IntT21', [UInt64], 'Public')).SetOffset(0x960) 
            ($TypeBuilder.DefineField('IntT22', [UInt64], 'Public')).SetOffset(0x968) 
            ($TypeBuilder.DefineField('IntNats', [UInt64], 'Public')).SetOffset(0x970)
            ($TypeBuilder.DefineField('Preds', [UInt64], 'Public')).SetOffset(0x978)  
            ($TypeBuilder.DefineField('BrRp', [UInt64], 'Public')).SetOffset(0x980)
            ($TypeBuilder.DefineField('BrS0', [UInt64], 'Public')).SetOffset(0x988)
            ($TypeBuilder.DefineField('BrS1', [UInt64], 'Public')).SetOffset(0x990) 
            ($TypeBuilder.DefineField('BrS2', [UInt64], 'Public')).SetOffset(0x998) 
            ($TypeBuilder.DefineField('BrS3', [UInt64], 'Public')).SetOffset(0x9a0) 
            ($TypeBuilder.DefineField('BrS4', [UInt64], 'Public')).SetOffset(0x9a8) 
            ($TypeBuilder.DefineField('BrT0', [UInt64], 'Public')).SetOffset(0x9b0)
            ($TypeBuilder.DefineField('BrT1', [UInt64], 'Public')).SetOffset(0x9b8)
            ($TypeBuilder.DefineField('ApUNAT', [UInt64], 'Public')).SetOffset(0x9c0)  
            ($TypeBuilder.DefineField('ApLC', [UInt64], 'Public')).SetOffset(0x9c8) 
            ($TypeBuilder.DefineField('ApEC', [UInt64], 'Public')).SetOffset(0x9d0)  
            ($TypeBuilder.DefineField('ApCCV', [UInt64], 'Public')).SetOffset(0x9d8)  
            ($TypeBuilder.DefineField('ApDCR', [UInt64], 'Public')).SetOffset(0x9e0)
            ($TypeBuilder.DefineField('RsPFS', [UInt64], 'Public')).SetOffset(0x9e8) 
            ($TypeBuilder.DefineField('RsBSP', [UInt64], 'Public')).SetOffset(0x9f0) 
            ($TypeBuilder.DefineField('RsBSPSTORE', [UInt64], 'Public')).SetOffset(0x9f8) 
            ($TypeBuilder.DefineField('RsRSC', [UInt64], 'Public')).SetOffset(0xa00)  
            ($TypeBuilder.DefineField('RsRNAT', [UInt64], 'Public')).SetOffset(0xa08)
            ($TypeBuilder.DefineField('StIPSR', [UInt64], 'Public')).SetOffset(0xa10)  
            ($TypeBuilder.DefineField('StIIP', [UInt64], 'Public')).SetOffset(0xa18) 
            ($TypeBuilder.DefineField('StIFS', [UInt64], 'Public')).SetOffset(0xa20)
            ($TypeBuilder.DefineField('StFCR', [UInt64], 'Public')).SetOffset(0xa28) 
            ($TypeBuilder.DefineField('Eflag', [UInt64], 'Public')).SetOffset(0xa30) 
            ($TypeBuilder.DefineField('SegCSD', [UInt64], 'Public')).SetOffset(0xa38)
            ($TypeBuilder.DefineField('SegSSD', [UInt64], 'Public')).SetOffset(0xa40)
            ($TypeBuilder.DefineField('Cflag', [UInt64], 'Public')).SetOffset(0xa48) 
            ($TypeBuilder.DefineField('StFSR', [UInt64], 'Public')).SetOffset(0xa50) 
            ($TypeBuilder.DefineField('StFIR', [UInt64], 'Public')).SetOffset(0xa58)
            ($TypeBuilder.DefineField('StFDR', [UInt64], 'Public')).SetOffset(0xa60)
            ($TypeBuilder.DefineField('UNUSEDPACK', [UInt64], 'Public')).SetOffset(0xa68)
            $Global:IA64_CONTEXT = $TypeBuilder.CreateType()
            #endregion IA64_CONTEXT
    
        #endregion STRUCTS

        function local:func {
        # A helper function used to reduce typing while defining function prototypes for Add-Win32Type.
            Param
            (
                [Parameter(Position = 0, Mandatory = $true)]
                [String]
                $DllName,

                [Parameter(Position = 1, Mandatory = $true)]
                [string]
                $FunctionName,

                [Parameter(Position = 2, Mandatory = $true)]
                [Type]
                $ReturnType,

                [Parameter(Position = 3)]
                [Type[]]
                $ParameterTypes,

                [Parameter(Position = 4)]
                [Runtime.InteropServices.CallingConvention]
                $NativeCallingConvention,

                [Parameter(Position = 5)]
                [Runtime.InteropServices.CharSet]
                $Charset,

                [Switch]
                $SetLastError
            )
            $Properties = @{
                DllName = $DllName
                FunctionName = $FunctionName
                ReturnType = $ReturnType
            }
            if ($ParameterTypes) { $Properties['ParameterTypes'] = $ParameterTypes }
            if ($NativeCallingConvention) { $Properties['NativeCallingConvention'] = $NativeCallingConvention }
            if ($Charset) { $Properties['Charset'] = $Charset }
            if ($SetLastError) { $Properties['SetLastError'] = $SetLastError }
            New-Object PSObject -Property $Properties
        }
        function local:Add-Win32Type {
            [OutputType([Hashtable])]
            Param(
                [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
                [String]
                $DllName,

                [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
                [String]
                $FunctionName,

                [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
                [Type]
                $ReturnType,

                [Parameter(ValueFromPipelineByPropertyName = $true)]
                [Type[]]
                $ParameterTypes,

                [Parameter(ValueFromPipelineByPropertyName = $true)]
                [Runtime.InteropServices.CallingConvention]
                $NativeCallingConvention = [Runtime.InteropServices.CallingConvention]::StdCall,

                [Parameter(ValueFromPipelineByPropertyName = $true)]
                [Runtime.InteropServices.CharSet]
                $Charset = [Runtime.InteropServices.CharSet]::Auto,

                [Parameter(ValueFromPipelineByPropertyName = $true)]
                [Switch]
                $SetLastError,

                [Parameter(Mandatory = $true)]
                [ValidateScript({($_ -is [Reflection.Emit.ModuleBuilder]) -or ($_ -is [Reflection.Assembly])})]
                $Module,

                [ValidateNotNull()]
                [String]
                $Namespace = ''
            )
            BEGIN { $TypeHash = @{} }
            PROCESS {
                if ($Module -is [Reflection.Assembly]) {
                    if ($Namespace) { $TypeHash[$DllName] = $Module.GetType("$Namespace.$DllName") }
                    else { $TypeHash[$DllName] = $Module.GetType($DllName) }
                }
                else # Define one type for each DLL
                {
                    if (!$TypeHash.ContainsKey($DllName)) {
                        if ($Namespace) { $TypeHash[$DllName] = $Module.DefineType("$Namespace.$DllName", 'Public,BeforeFieldInit') }
                        else { $TypeHash[$DllName] = $Module.DefineType($DllName, 'Public,BeforeFieldInit') }
                    }

                    $Method = $TypeHash[$DllName].DefineMethod($FunctionName, 'Public,Static,PinvokeImpl', $ReturnType, $ParameterTypes)

                    # Make each ByRef parameter an Out parameter
                    $i = 1
                    foreach($Parameter in $ParameterTypes) { if ($Parameter.IsByRef) { [void]$Method.DefineParameter($i, 'Out', $null) } $i++ }

                    $DllImport = [Runtime.InteropServices.DllImportAttribute]
                    $SetLastErrorField = $DllImport.GetField('SetLastError')
                    $CallingConventionField = $DllImport.GetField('CallingConvention')
                    $CharsetField = $DllImport.GetField('CharSet')
                    if ($SetLastError) { $SLEValue = $true } else { $SLEValue = $false }

                    # Equivalent to C# version of [DllImport(DllName)]
                    $Constructor = [Runtime.InteropServices.DllImportAttribute].GetConstructor([String])
                    $DllImportAttribute = New-Object Reflection.Emit.CustomAttributeBuilder($Constructor, $DllName, [Reflection.PropertyInfo[]] @(), [Object[]] @(), [Reflection.FieldInfo[]] @($SetLastErrorField, $CallingConventionField, $CharsetField), [Object[]] @($SLEValue, ([Runtime.InteropServices.CallingConvention] $NativeCallingConvention), ([Runtime.InteropServices.CharSet] $Charset)))
                    $Method.SetCustomAttribute($DllImportAttribute)
                }
            }
            END {
                if ($Module -is [Reflection.Assembly]) { return $TypeHash }
                $ReturnTypes = @{}
                foreach ($Key in $TypeHash.Keys) {
                    $Type = $TypeHash[$Key].CreateType()
                    $ReturnTypes[$Key] = $Type
                }
            return $ReturnTypes
            }
        }
        function local:Get-DelegateType {
            Param
            (
                [OutputType([Type])]
            
                [Parameter( Position = 0)]
                [Type[]]
                $Parameters = (New-Object Type[](0)),
            
                [Parameter( Position = 1 )]
                [Type]
                $ReturnType = [Void]
            )
            $Domain = [AppDomain]::CurrentDomain
            $DynAssembly = New-Object System.Reflection.AssemblyName('ReflectedDelegate')
            $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
            $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
            $TypeBuilder = $ModuleBuilder.DefineType('MyDelegateType', 'Class, Public, Sealed, AnsiClass, AutoClass', [MulticastDelegate])
            $ConstructorBuilder = $TypeBuilder.DefineConstructor('RTSpecialName, HideBySig, Public', [Reflection.CallingConventions]::Standard, $Parameters)
            $ConstructorBuilder.SetImplementationFlags('Runtime, Managed')
            $MethodBuilder = $TypeBuilder.DefineMethod('Invoke', 'Public, HideBySig, NewSlot, Virtual', $ReturnType, $Parameters)
            $MethodBuilder.SetImplementationFlags('Runtime, Managed')        
            $TypeBuilder.CreateType()
        }

        $FunctionDefinitions = @(
            #Kernel32
            (func kernel32 OpenProcess ([IntPtr]) @([Int32], [Bool], [Int32]) -SetLastError),
            (func kernel32 OpenThread ([IntPtr]) @([Int32], [Bool], [Int32]) -SetLastError),
            (func kernel32 CloseHandle ([Bool]) @([IntPtr]) -SetLastError),
            (func kernel32 Wow64SuspendThread ([UInt32]) @([IntPtr]) -SetLastError),
            (func kernel32 SuspendThread ([UInt32]) @([IntPtr]) -SetLastError),
            (func kernel32 ResumeThread ([UInt32]) @([IntPtr]) -SetLastError),
            (func kernel32 Wow64GetThreadContext ([Bool]) @([IntPtr], [IntPtr]) -SetLastError),
            (func kernel32 GetThreadContext ([Bool]) @([IntPtr], [IntPtr]) -SetLastError),
            (func kernel32 GetSystemInfo ([Void]) @($SYSTEM_INFO.MakeByRefType()) -SetLastError),
            (func kernel32 IsWow64Process ([Bool]) @([IntPtr], [Bool].MakeByRefType()) -SetLastError),

            #Psapi
            (func psapi EnumProcessModulesEx ([Bool]) @([IntPtr], [IntPtr].MakeArrayType(), [UInt32], [UInt32].MakeByRefType(), [Int32]) -SetLastError),
            (func psapi GetModuleInformation ([Bool]) @([IntPtr], [IntPtr], $MODULE_INFO.MakeByRefType(), [UInt32]) -SetLastError), 
            (func psapi GetModuleBaseNameW ([UInt32]) @([IntPtr], [IntPtr], [Text.StringBuilder], [Int32]) -Charset Unicode -SetLastError),
            (func psapi GetModuleFileNameExW ([UInt32]) @([IntPtr], [IntPtr], [Text.StringBuilder], [Int32]) -Charset Unicode -SetLastError),
            (func psapi GetMappedFileNameW ([UInt32]) @([IntPtr], [IntPtr], [Text.StringBuilder], [Int32]) -Charset Unicode -SetLastError),

            #DbgHelp
            (func dbghelp SymInitialize ([Bool]) @([IntPtr], [String], [Bool]) -SetLastError),
            (func dbghelp SymCleanup ([Bool]) @([IntPtr]) -SetLastError),
            (func dbghelp SymFunctionTableAccess64 ([IntPtr]) @([IntPtr], [UInt64]) -SetLastError),
            (func dbghelp SymGetModuleBase64 ([UInt64]) @([IntPtr], [UInt64]) -SetLastError),
            (func dbghelp SymGetSymFromAddr64 ([Bool]) @([IntPtr], [UInt64], [UInt64], [IntPtr]) -SetLastError),
            (func dbghelp SymLoadModuleEx ([UInt64]) @([IntPtr], [IntPtr], [String], [String], [IntPtr], [Int32], [IntPtr], [Int32]) -SetLastError),
            (func dbghelp StackWalk64 ([Bool]) @([UInt32], [IntPtr], [IntPtr], [IntPtr], [IntPtr], [MulticastDelegate], [MulticastDelegate], [MulticastDelegate], [MulticastDelegate]))
        )
        $Types = $FunctionDefinitions | Add-Win32Type -Module $ModuleBuilder -Namespace 'Win32'
        $Global:Kernel32 = $Types['kernel32']
        $Global:Psapi = $Types['psapi']
        $Global:Dbghelp = $Types['dbghelp']

        function local:Trace-Thread {
            Param(
                [Parameter()]
                [IntPtr]$ProcessHandle, 

                [Parameter()]
                [Int]$ThreadId,
                     
                [Parameter()]
                [Int]$ProcessId
            ) 

            #region HELPERS
            function local:Get-SystemInfo {
                $SystemInfo = [Activator]::CreateInstance($SYSTEM_INFO)
                [void]$Kernel32::GetSystemInfo([ref]$SystemInfo)

                Write-Output $SystemInfo
                Remove-Variable -Name SystemInfo
            }
            function local:Import-ModuleSymbols ($hProcess) {  

                #Initialize parameters for EPM
                $cbNeeded = 0
                [void]$Psapi::EnumProcessModulesEx($hProcess, $null, 0, [ref]$cbNeeded, 3)
                $ArraySize = $cbNeeded / [IntPtr]::Size

                $hModules = New-Object IntPtr[] $ArraySize

                $cb = $cbNeeded;
                [void]$Psapi::EnumProcessModulesEx($hProcess, $hModules, $cb, [ref]$cbNeeded, 3);
                for ($i = 0; $i -lt $ArraySize; $i++)
                {
                    $ModInfo = [Activator]::CreateInstance($MODULE_INFO)
                    $lpFileName = [Activator]::CreateInstance([Text.StringBuilder], 256)
                    $lpModuleBaseName = [Activator]::CreateInstance([Text.StringBuilder], 32)

                    [void]$Psapi::GetModuleFileNameExW($hProcess, $hModules[$i], $lpFileName, $lpFileName.Capacity)
                    [void]$Psapi::GetModuleBaseNameW($hProcess, $hModules[$i], $lpModuleBaseName, $lpModuleBaseName.Capacity)
                    [void]$Psapi::GetModuleInformation($hProcess, $hModules[$i], [ref]$ModInfo,  [Runtime.InteropServices.Marshal]::SizeOf($ModInfo))
                    [void]$Dbghelp::SymLoadModuleEx($hProcess, [IntPtr]::Zero, $lpFileName.ToString(), $lpModuleBaseName.ToString(), $ModInfo.lpBaseOfDll, [Int32]$ModInfo.SizeOfImage, [IntPtr]::Zero, 0)
                        
                    Remove-Variable -Name ModInfo,lpFileName,lpModuleBaseName
                }
                Remove-Variable -Name hModules
            }    
            function local:Convert-UIntToInt {
	            Param([Parameter(Position = 0, Mandatory = $true)][UInt64]$Value)
		
	            [Byte[]]$ValueBytes = [BitConverter]::GetBytes($Value)
	            return ([BitConverter]::ToInt64($ValueBytes, 0))
            }
            function local:Initialize-Stackframe ($OffsetPC, $OffsetFrame, $OffsetStack, $OffsetBStore) {

                $StackFrame = [Activator]::CreateInstance($STACKFRAME64)
                $Addr64 = [Activator]::CreateInstance($ADDRESS64)
                $Addr64.Mode = 0x03
    
                $Addr64.Offset = $OffsetPC
                $StackFrame.AddrPC = $Addr64

                $Addr64.Offset = $OffsetFrame
                $StackFrame.AddrFrame = $Addr64

                $Addr64.Offset = $OffsetStack
                $StackFrame.AddrStack = $Addr64

                $Addr64.Offset = $OffsetBStore
                $StackFrame.AddrBStore = $Addr64
    
                Write-Output $StackFrame
                Remove-Variable -Name StackFrame,Addr64
            }
            function local:Get-SymbolFromAddress ($hProcess, $Address) {
    
                #Initialize params for SymGetSymFromAddr64
                $Symbol = [Activator]::CreateInstance($IMAGEHLP_SYMBOLW64)
                $Symbol.SizeOfStruct = [Runtime.InteropServices.Marshal]::SizeOf($Symbol)
                $Symbol.MaxNameLength = 32

                $lpSymbol = [Runtime.InteropServices.Marshal]::AllocHGlobal($Symbol.SizeOfStruct)
                [Runtime.InteropServices.Marshal]::StructureToPtr($Symbol, $lpSymbol, $false)

                [void]$Dbghelp::SymGetSymFromAddr64($hProcess, $Address, 0, $lpSymbol)
            
                $Symbol = [Runtime.InteropServices.Marshal]::PtrToStructure($lpSymbol, [Type]$IMAGEHLP_SYMBOLW64)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($lpSymbol)

                Write-Output $Symbol
                $Symbol = $null
            }
            #endregion HELPERS

            $SymFunctionTableAccess64Delegate = Get-DelegateType @([IntPtr], [UInt64]) ([IntPtr])
            $Action = { Param([IntPtr]$hProcess, [UInt64]$AddrBase) $Dbghelp::SymFunctionTableAccess64($hProcess, $AddrBase) }
            $FunctionTableAccess = $Action -as $SymFunctionTableAccess64Delegate

            $SymGetModuleBase64Delegate = Get-DelegateType @([IntPtr], [UInt64]) ([UInt64])
            $Action = { Param([IntPtr]$hProcess, [UInt64]$Address) $Dbghelp::SymGetModuleBase64($hProcess, $Address) }
            $GetModuleBase = $Action -as $SymGetModuleBase64Delegate

            #Initialize some things
            $lpContextRecord = [Activator]::CreateInstance([IntPtr])
            $Stackframe = [Activator]::CreateInstance($STACKFRAME64)
            $ImageType = 0
            $Wow64 = $false
            $SystemInfo = Get-SystemInfo

            #Get thread handle
            if (($hThread = $Kernel32::OpenThread(0x1F03FF, $false, $ThreadId)) -eq 0) {
                Write-Error "Unable to open handle for thread $ThreadId."
                break
            }

            #If not x86 processor, check for Wow64 (x86) process
            if ($SystemInfo.ProcessorArchitecture -ne 0) { [void]$Kernel32::IsWow64Process($hProcess, [ref]$Wow64) }

            if ($Wow64) {

                $ImageType = 0x014C #I386/x86

                Import-ModuleSymbols $hProcess

                #Initialize x86 context in memory
                $ContextRecord = [Activator]::CreateInstance($X86_CONTEXT)
                $ContextRecord.ContextFlags = 0x1003F #All
                $lpContextRecord = [Runtime.InteropServices.Marshal]::AllocHGlobal([Runtime.InteropServices.Marshal]::SizeOf($ContextRecord))
                [Runtime.InteropServices.Marshal]::StructureToPtr($ContextRecord, $lpContextRecord, $false)

                [void]$Kernel32::Wow64SuspendThread($hThread)
                [void]$Kernel32::Wow64GetThreadContext($hThread, $lpContextRecord)

                $ContextRecord = [Runtime.InteropServices.Marshal]::PtrToStructure($lpContextRecord, [Type]$X86_CONTEXT)
                $Stackframe = Initialize-Stackframe $ContextRecord.Eip $ContextRecord.Esp $ContextRecord.Ebp $null
            }

            #If x86 processor
            elseif ($SystemInfo.ProcessorArchitecture -eq 0) {

                $ImageType = 0x014C #I386/x86

                Import-ModuleSymbols $hProcess

                #Initialize x86 context in memory
                $ContextRecord = [Activator]::CreateInstance($X86_CONTEXT)
                $ContextRecord.ContextFlags = 0x1003F #All
                $lpContextRecord = [Runtime.InteropServices.Marshal]::AllocHGlobal([Runtime.InteropServices.Marshal]::SizeOf($ContextRecord))
                [Runtime.InteropServices.Marshal]::StructureToPtr($ContextRecord, $lpContextRecord, $false)

                [void]$Kernel32::SuspendThread($hThread)
                [void]$Kernel32::GetThreadContext($hThread, $lpContextRecord)

                $ContextRecord = [Runtime.InteropServices.Marshal]::PtrToStructure($lpContextRecord, [Type]$X86_CONTEXT)
                $Stackframe = Initialize-Stackframe $ContextRecord.Eip $ContextRecord.Esp $ContextRecord.Ebp $null
            }

            #If AMD64 processor
            elseif ($SystemInfo.ProcessorArchitecture -eq 9) {

                $ImageType = 0x8664 #AMD64, interesting that MSFT chose the hex 8664 i.e. x86_64 for this constant...

                Import-ModuleSymbols $hProcess

                #Initialize AMD64 context in memory
                $ContextRecord = [Activator]::CreateInstance($AMD64_CONTEXT)
                $ContextRecord.ContextFlags = 0x10003B #All
                $lpContextRecord = [Runtime.InteropServices.Marshal]::AllocHGlobal([Runtime.InteropServices.Marshal]::SizeOf($ContextRecord))
                [Runtime.InteropServices.Marshal]::StructureToPtr($ContextRecord, $lpContextRecord, $false)

                [void]$Kernel32::SuspendThread($hThread)
                [void]$Kernel32::GetThreadContext($hThread, $lpContextRecord)

                $ContextRecord = [Runtime.InteropServices.Marshal]::PtrToStructure($lpContextRecord, [Type]$AMD64_CONTEXT)
                $Stackframe = Initialize-Stackframe $ContextRecord.Rip $ContextRecord.Rsp $ContextRecord.Rsp $null
            }

            #If IA64 processor
            elseif ($SystemInfo.ProcessorArchitecture -eq 6) {

                $ImageType = 0x0200 #IA64

                Import-ModuleSymbols $hProcess

                #Initialize IA64 context in memory
                $ContextRecord = [Activator]::CreateInstance($IA64_CONTEXT)
                $ContextRecord.ContextFlags = 0x8003D #All
                $lpContextRecord = [Runtime.InteropServices.Marshal]::AllocHGlobal([Runtime.InteropServices.Marshal]::SizeOf($ContextRecord))
                [Runtime.InteropServices.Marshal]::StructureToPtr($ContextRecord, $lpContextRecord, $false)

                [void]$Kernel32::SuspendThread($hThread)
                [void]$Kernel32::GetThreadContext($hThread, $lpContextRecord)

                $ContextRecord = [Runtime.InteropServices.Marshal]::PtrToStructure($lpContextRecord, [Type]$IA64_CONTEXT)
                $Stackframe = Initialize-Stackframe $ContextRecord.StIIP $ContextRecord.IntSp $ContextRecord.RsBSP $ContextRecord.IntSp
            }
            $SystemInfo = $null

            #Marshal Stackframe to pointer
            $lpStackFrame = [Runtime.InteropServices.Marshal]::AllocHGlobal([Runtime.InteropServices.Marshal]::SizeOf($Stackframe))
            [Runtime.InteropServices.Marshal]::StructureToPtr($Stackframe, $lpStackFrame, $false)

            #Walk the Stack
            while ($true)
            {
                #Get Stackframe
                [void]$Dbghelp::StackWalk64($ImageType, $hProcess, $hThread, $lpStackFrame, $lpContextRecord, $null, $FunctionTableAccess, $GetModuleBase, $null)
                $Stackframe = [Runtime.InteropServices.Marshal]::PtrToStructure($lpStackFrame, [Type]$STACKFRAME64)

                if ($Stackframe.AddrReturn.Offset -eq 0) { break } #End of stack reached

                $MappedFile = [Activator]::CreateInstance([Text.StringBuilder], 256)
                [void]$Psapi::GetMappedFileNameW($hProcess, [IntPtr](Convert-UIntToInt $Stackframe.AddrPC.Offset), $MappedFile, $MappedFile.Capacity)

                $Symbol = Get-SymbolFromAddress $hProcess $Stackframe.AddrPC.Offset
                $SymbolName = (([String]$Symbol.Name).Replace(' ','')).TrimEnd([Byte]0)

                $Properties = @{
                    ProcessId  = $ProcessId
                    ThreadId   = $ThreadId
                    AddrPC     = $Stackframe.AddrPC.Offset
                    AddrReturn = $Stackframe.AddrReturn.Offset
                    Symbol     = $SymbolName
                    MappedFile = $MappedFile
                }
                New-Object PSObject -Property $Properties
            }

            #Cleanup
            [Runtime.InteropServices.Marshal]::FreeHGlobal($lpStackFrame)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($lpContextRecord)
            [void]$Kernel32::ResumeThread($hThread)
            [void]$Kernel32::CloseHandle($hThread)
        }  
    
        if ($Name -ne "") {
            foreach ($Process in (Get-Process -Name $Name)) {
                if (($hProcess = $Kernel32::OpenProcess(0x1F0FFF, $false, $Process.Id)) -eq 0) {
                    Write-Error "Unable to obtain handle for process $($Process.Id)."
                    continue
                }
                [void]$Dbghelp::SymInitialize($hProcess, $null, $false)

                $Process.Threads | ForEach-Object { Trace-Thread -ProcessHandle $hProcess -ThreadId $_.Id -ProcessId $Process.Id }
                    
                [void]$Dbghelp::SymCleanup($hProcess)
                if (!$Kernel32::CloseHandle($hProcess)) { Write-Error "Failed to close handle for process $($Process.Id)." }
                [GC]::Collect()
            }
            break
        }
        elseif ($Id -ne -1) {
            $Process = Get-Process -Id $Id
            if (($hProcess = $Kernel32::OpenProcess(0x1F0FFF, $false, $Process.Id)) -eq 0) {
                Write-Error "Unable to obtain handle for process $($Process.Id)."
                break
            }
            [void]$Dbghelp::SymInitialize($hProcess, $null, $false)

            $Process.Threads | ForEach-Object { Trace-Thread -ProcessHandle $hProcess -ThreadId $_.Id -ProcessId $Process.Id }
                    
            [void]$Dbghelp::SymCleanup($hProcess)
            if (!$Kernel32::CloseHandle($hProcess)) { Write-Error "Failed to close handle for process $($Process.Id)." }
            [GC]::Collect()
            break
        }
    }#End RemoteScriptBlock

    if ($PSBoundParameters['TargetList']) {
        if ($ConfirmTargets.IsPresent) { $TargetList = Confirm-Targets $TargetList }        
        
        $ReturnedObjects = New-Object Collections.ArrayList
        $HostsRemaining = [Collections.ArrayList]$TargetList
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)

        Invoke-Command -ComputerName $TargetList -ScriptBlock $RemoteScriptBlock -ArgumentList @($Name, $Id) -SessionOption (New-PSSessionOption -NoMachineProfile) -ThrottleLimit $ThrottleLimit |
        ForEach-Object { 
            if ($HostsRemaining -contains $_.PSComputerName) { $HostsRemaining.Remove($_.PSComputerName) }
            [void]$ReturnedObjects.Add($_)
            Write-Progress -Activity "Waiting for jobs to complete..." -Status "Hosts Remaining: $($HostsRemaining.Count)" -PercentComplete (($TargetList.Count - $HostsRemaining.Count) / $TargetList.Count * 100)
        }
        Write-Progress -Activity "Waiting for jobs to complete..." -Status "Completed" -Completed
    }
    else { $ReturnedObjects = Invoke-Command -ScriptBlock $RemoteScriptBlock -ArgumentList @($Name, $Id) }

    Get-ErrorHost -ErrorFileVerbose $ErrorFileVerbose -ErrorFileHosts $ErrorFileHosts
    
    if ($ReturnedObjects -ne $null) {
        if ($PSBoundParameters['CSV']) { $ReturnedObjects | Export-Csv -Path $OutputFilePath -Append -NoTypeInformation -ErrorAction SilentlyContinue }
        elseif ($PSBoundParameters['TXT']) { $ReturnedObjects | Out-File -FilePath $OutputFilePath -Append -ErrorAction SilentlyContinue }
        else { Write-Output $ReturnedObjects }
    }

    [GC]::Collect()
    $ScriptTime.Stop()
    Write-Verbose "Done, execution time: $($ScriptTime.Elapsed)"
}