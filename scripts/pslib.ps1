# pslib
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
$PSDefaultParameterValues['*:Verbose'] = $false

# For backward compatibility with PowerShell versions less than 3.0
if (!(Test-Path Variable:PSScriptRoot)) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

# https://gist.github.com/sayedihashimi/02e98613efcb7280d706
function Resolve-FullPath {
    [CmdletBinding()]
    param
    (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true)]
        [string] $Path
    )

    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

# https://stackoverflow.com/questions/42488323/how-to-install-module-into-custom-directory
function Install-ModuleToDirectory {
    [CmdletBinding()]
    [OutputType('System.Management.Automation.PSModuleInfo')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $Name,

        [Parameter(Mandatory = $true)]
        [ValidateScript( { Test-Path $_ })]
        [ValidateNotNullOrEmpty()]
        $Destination
    )

    # Is the module already installed?
    if (-not (Test-Path (Join-Path $Destination $Name))) {
        # Install the module to the custom destination.
        Find-Module -Name $Name -Repository 'PSGallery' | Save-Module -Path $Destination
    }

    # Import the module from the custom directory.
    Import-Module -FullyQualifiedName (Resolve-FullPath (Join-Path $Destination $Name))

    return (Get-Module -Name $Name)
}

<#PSScriptInfo

.VERSION 0.0.3

.GUID c62ee4be-fc92-4ef8-aa20-af179105702a

.AUTHOR Stuart Leeks

.COMPANYNAME

.COPYRIGHT

.TAGS docker

.LICENSEURI https://github.com/stuartleeks/ConvertFrom-Docker/blob/master/LICENSE.md

.PROJECTURI https://github.com/stuartleeks/ConvertFrom-Docker

.ICONURI

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


#>

<#

.DESCRIPTION
 Script to parse docker output into PowerShell objects

#>

function local:PascalName($name) {
    $parts = $name.Split(" ")
    for ($i = 0 ; $i -lt $parts.Length ; $i++) {
        $parts[$i] = [char]::ToUpper($parts[$i][0]) + $parts[$i].SubString(1).ToLower();
    }
    $parts -join ""
}
function local:GetHeaderBreak($headerRow, $startPoint = 0) {
    $i = $startPoint
    while ( $i + 1 -lt $headerRow.Length) {
        if ($headerRow[$i] -eq ' ' -and $headerRow[$i + 1] -eq ' ') {
            return $i
            break
        }
        $i += 1
    }
    return -1
}
function local:GetHeaderNonBreak($headerRow, $startPoint = 0) {
    $i = $startPoint
    while ( $i + 1 -lt $headerRow.Length) {
        if ($headerRow[$i] -ne ' ') {
            return $i
            break
        }
        $i += 1
    }
    return -1
}
function local:GetColumnInfo($headerRow) {
    $lastIndex = 0
    $i = 0
    while ($i -lt $headerRow.Length) {
        $i = GetHeaderBreak $headerRow $lastIndex
        if ($i -lt 0) {
            $name = $headerRow.Substring($lastIndex)
            New-Object PSObject -Property @{ HeaderName = $name; Name = PascalName $name; Start = $lastIndex; End = -1 }
            break
        }
        else {
            $name = $headerRow.Substring($lastIndex, $i - $lastIndex)
            $temp = $lastIndex
            $lastIndex = GetHeaderNonBreak $headerRow $i
            New-Object PSObject -Property @{ HeaderName = $name; Name = PascalName $name; Start = $temp; End = $lastIndex }
        }
    }
}
function local:ParseRow($row, $columnInfo) {
    $values = @{ }
    $columnInfo | ForEach-Object {
        if ($_.End -lt 0) {
            $len = $row.Length - $_.Start
        }
        else {
            $len = $_.End - $_.Start
        }
        $values[$_.Name] = $row.SubString($_.Start, $len).Trim()
    }
    New-Object PSObject -Property $values
}
function ConvertFrom-Docker() {
    begin {
        $positions = $null;
    }
    process {
        if ($null -eq $positions) {
            # header row => determine column positions
            $positions = GetColumnInfo -headerRow $_  #-propertyNames $propertyNames
        }
        else {
            # data row => output!
            ParseRow -row $_ -columnInfo $positions
        }
    }
    end {
    }
}

function Test-DockerImage {
    [CmdletBinding()]
    param
    (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true)]
        [string] $ImageName
    )
    $images = @(docker images "$ImageName" | ConvertFrom-Docker)
    return ($images.Count -gt 0);
}

function Get-DockerContainer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch] $Running,

        [Parameter(Mandatory = $false)]
        [switch] $Latest,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory = $false)]
        [ValidateSet("created", "restarting", "running", "removing", "paused", "exited", "dead")]
        [string] $Status,

        [Parameter(Mandatory = $false)]
        [string[]]
        $DockerArguments
    )

    $dockerArgs = New-Object System.Collections.ArrayList

    if ( $Running -eq $false ) {
        [void] $dockerArgs.Add( '--all' )
    }

    if ( $Latest ) {
        [void] $dockerArgs.Add( '--latest' )
    }

    if ( $Name ) {
        [void] $dockerArgs.Add( "--filter=name=$Name" )
    }

    if ( $Status ) {
        [void] $dockerArgs.Add( "--filter=status=$Status" )
    }

    if ($DockerArguments -and $DockerArguments.Count -gt 0) {
        [void] $dockerArgs.AddRange($DockerArguments)
    }

    [void] $dockerArgs.AddRange( ("--no-trunc", '--format="{{json .}}') )

    & docker ps $dockerArgs | ConvertFrom-Json |
    ForEach-Object {
        New-Object -TypeName PSObject -Property @{
            Command      = $_.Command
            CreatedAt    = $_.CreatedAt
            Id           = $_.ID
            Image        = $_.Image
            Labels       = $_.Labels -split ','
            LocalVolumes = $_.LocalVolumes -split ','
            Mounts       = $_.Mounts -split ','
            Names        = $_.Names -split ','
            Networks     = $_.Networks -split ','
            Ports        = $_.Ports
            RunningFor   = $_.RunningFor
            Size         = $_.Size
            Status       = $_.Status
        } | Write-Output
    } | Write-Output
}

function New-DockerContainer {
    [CmdletBinding()]
    param (

        [Parameter( Mandatory = $false, ValueFromPipelineByPropertyName = $true )]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter( Mandatory = $true, ValueFromPipelineByPropertyName = $true )]
        [ValidateNotNullOrEmpty()]
        [Alias( 'Image' )]
        [string] $ImageName,

        [Parameter( Mandatory = $false, ValueFromPipelineByPropertyName = $true )]
        [ValidateNotNullOrEmpty()]
        [string] $Entrypoint,

        [Parameter( Mandatory = $false, ValueFromPipelineByPropertyName = $true )]
        [ValidateNotNullOrEmpty()]
        [hashtable] $Environment,

        [Parameter( Mandatory = $false, ValueFromPipelineByPropertyName = $true )]
        [ValidateNotNullOrEmpty()]
        [hashtable] $Ports,

        [Parameter( Mandatory = $false, ValueFromPipelineByPropertyName = $true )]
        [ValidateNotNullOrEmpty()]
        [hashtable] $Volumes,

        [Parameter( Mandatory = $false, ValueFromPipelineByPropertyName = $true )]
        [switch] $Detach,

        [Parameter( Mandatory = $false, ValueFromPipelineByPropertyName = $true )]
        [switch] $Interactive,

        [Parameter( Mandatory = $false, ValueFromPipelineByPropertyName = $true )]
        [switch] $Tty,

        [Parameter( Mandatory = $false, ValueFromPipelineByPropertyName = $true )]
        [switch] $Remove,

        [Parameter(Mandatory = $false)]
        [string[]]
        $DockerArguments,

        [Parameter(Mandatory = $false)]
        [string[]]
        $ContainerArguments
    )

    $dockerArgs = New-Object System.Collections.ArrayList

    if ( $Name ) {
        [void] $dockerArgs.Add(  "--name=$Name" )
    }

    if ( $Entrypoint ) {
        [void] $dockerArgs.Add(  "--entrypoint=$Entrypoint" )
    }

    if ( $Environment ) {
        foreach ( $item in $Environment.GetEnumerator() ) {
            [void] $dockerArgs.Add( "--env=`"$( $item.Name)=$( $item.Value )`"")
        }
    }

    if ( $Ports ) {
        foreach ( $item in $Ports.GetEnumerator() ) {
            [void] $dockerArgs.Add( "--publish=$( $item.Name):$( $item.Value )")
        }
    }

    if ( $Volumes ) {
        foreach ( $volume in $Volumes.GetEnumerator() ) {
            [void] $dockerArgs.Add( "--volume=$( $volume.Name ):$( $volume.Value )" )
        }
    }

    if ( $Detach ) {
        [void] $dockerArgs.Add( '--detach' )
    }

    if ( $Interactive ) {
        [void] $dockerArgs.Add( '--interactive' )
    }

    if ( $Tty ) {
        [void] $dockerArgs.Add( '--tty' )
    }

    if ( $Remove ) {
        [void] $dockerArgs.Add( '--rm' )
    }

    if ($DockerArguments -and $DockerArguments.Count -gt 0) {
        [void] $dockerArgs.AddRange($DockerArguments)
    }

    [void] $dockerArgs.Add( $ImageName )

    if ($ContainerArguments -and $ContainerArguments.Count -gt 0) {
        [void] $dockerArgs.AddRange($ContainerArguments)
    }

    Write-Verbose "docker run $($dockerArgs -join ' ')"

    & docker run $dockerArgs
    if (! $?) {
        Write-Error -Message "Could not run docker container: docker run $($dockerArgs -join ' ')" -Category NotSpecified -ErrorAction SilentlyContinue
        $PSCmdlet.WriteError($Global:Error[0])
    }
}

function Remove-DockerContainer {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory = $true, ValueFromPipelineByPropertyName = $true )]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter( Mandatory = $false )]
        [switch] $Force
    )

    $dockerArgs = New-Object System.Collections.ArrayList

    if ( $Force ) {
        [void] $dockerArgs.Add(  "--force" )
    }

    [void] $dockerArgs.Add( $Name )

    $cmd = "docker rm $($dockerArgs -join ' ')"

    Write-Verbose "$cmd"

    & docker rm $dockerArgs
    if (! $?) {
        Write-Error -Message "Could not remove docker container ${Name}: $cmd" -Category NotSpecified -ErrorAction SilentlyContinue
        $PSCmdlet.WriteError($Global:Error[0])
    }
    else {
        Write-Verbose "Docker container $Name removed"
    }
}

function Stop-DockerContainer {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory = $true, ValueFromPipelineByPropertyName = $true )]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter( Mandatory = $false )]
        [int] $Time = 10
    )

    $dockerArgs = New-Object System.Collections.ArrayList

    [void] $dockerArgs.Add(  "--time=$Time" )
    [void] $dockerArgs.Add( $Name )

    $cmd = "docker rm $($dockerArgs -join ' ')"

    Write-Verbose "$cmd"

    & docker stop $dockerArgs
    if (! $?) {
        Write-Error -Message "Could not stop docker container ${Name}: $cmd" -Category NotSpecified -ErrorAction SilentlyContinue
        $PSCmdlet.WriteError($Global:Error[0])
    }
    else {
        Write-Verbose "Docker container $Name stopped"
    }
}

# https://github.com/lukesampson/scoop
# adapted from http://hg.python.org/cpython/file/2.7/Lib/getopt.py
# argv:
#    array of arguments
# shortopts:
#    string of single-letter options. options that take a parameter
#    should be follow by ':'
# longopts:
#    array of strings that are long-form options. options that take
#    a parameter should end with '='
# returns @(opts hash, remaining_args array, error string)
function getopt($argv, $shortopts, $longopts) {
    $opts = @{ }; $rem = @()

    function err($msg) {
        $opts, $rem, $msg
    }

    function regex_escape($str) {
        return [regex]::escape($str)
    }

    # ensure these are arrays
    $argv = @($argv)
    $longopts = @($longopts)
    $end_of_args = $false

    for ($i = 0; $i -lt $argv.length; $i++) {
        $arg = $argv[$i]
        if ($null -eq $arg) { continue }
        # don't try to parse array arguments
        if ($arg -is [array]) { $rem += , $arg; continue }
        if ($arg -is [int]) { $rem += $arg; continue }
        if ($arg -is [decimal]) { $rem += $arg; continue }

        if ($end_of_args) {
             $rem += $arg
        } elseif ($arg -eq '--' -or $arg -eq '---') {
            $end_of_args = $true
        } elseif ($arg.startswith('--')) {
            $name = $arg.substring(2)

            $longopt = $longopts | Where-Object { $_ -match "^$name=?$" }

            if ($longopt) {
                if ($longopt.endswith('=')) {
                    # requires arg
                    if ($i -eq $argv.length - 1) {
                        return err "Option --$name requires an argument."
                    }
                    $opts.$name = $argv[++$i]
                }
                else {
                    $opts.$name = $true
                }
            }
            else {
                return err "Option --$name not recognized."
            }
        }
        elseif ($arg.startswith('-') -and $arg -ne '-') {
            for ($j = 1; $j -lt $arg.length; $j++) {
                $letter = $arg[$j].tostring()

                if ($shortopts -match "$(regex_escape $letter)`:?") {
                    $shortopt = $matches[0]
                    if ($shortopt.Length -gt 1 -and $shortopt[1] -eq ':') {
                        if ($j -ne $arg.length - 1 -or $i -eq $argv.length - 1) {
                            return err "Option -$letter requires an argument."
                        }
                        $opts.$letter = $argv[++$i]
                    }
                    else {
                        $opts.$letter = $true
                    }
                }
                else {
                    return err "Option -$letter not recognized."
                }
            }
        }
        else {
            $rem += $arg
        }
    }

    $opts, $rem
}

#https://gallery.technet.microsoft.com/Merge-Hashtables-Combine-e24e8aa7
#requires -Version 2.0
<#
    .NOTES
    ===========================================================================
     Filename              : Merge-Hashtables.ps1
     Created on            : 2014-09-04
     Created by            : Frank Peter Schultze
    ===========================================================================

    .SYNOPSIS
        Create a single hashtable from two hashtables where the second given
        hashtable will override.

    .DESCRIPTION
        Create a single hashtable from two hashtables. In case of duplicate keys
        the function the second hashtable's key values "win". Merge-Hashtables
        supports nested hashtables.

    .EXAMPLE
        $configData = Merge-Hashtables -First $defaultData -Second $overrideData

    .INPUTS
        None

    .OUTPUTS
        System.Collections.Hashtable
#>
function Merge-Hashtables {
    [CmdletBinding()]
    Param
    (
        #Identifies the first hashtable
        [Parameter(Mandatory = $true)]
        [Hashtable]
        $First
        ,
        #Identifies the second hashtable
        [Parameter(Mandatory = $true)]
        [Hashtable]
        $Second
    )

    function Set-Keys ($First, $Second) {
        @($First.Keys) | Where-Object {
            $Second.ContainsKey($_)
        } | ForEach-Object {
            if (($First.$_ -is [Hashtable]) -and ($Second.$_ -is [Hashtable])) {
                Set-Keys -First $First.$_ -Second $Second.$_
            }
            else {
                $First.Remove($_)
                $First.Add($_, $Second.$_)
            }
        }
    }

    function Add-Keys ($First, $Second) {
        @($Second.Keys) | ForEach-Object {
            if ($First.ContainsKey($_)) {
                if (($Second.$_ -is [Hashtable]) -and ($First.$_ -is [Hashtable])) {
                    Add-Keys -First $First.$_ -Second $Second.$_
                }
            }
            else {
                $First.Add($_, $Second.$_)
            }
        }
    }

    # Do not touch the original hashtables
    $firstClone = $First.Clone()
    $secondClone = $Second.Clone()

    # Bring modified keys from secondClone to firstClone
    Set-Keys -First $firstClone -Second $secondClone

    # Bring additional keys from secondClone to firstClone
    Add-Keys -First $firstClone -Second $secondClone

    # return firstClone
    $firstClone
}

# https://devblogs.microsoft.com/scripting/use-powershell-to-work-with-any-ini-file/

Function Get-IniContent {
    <#
    .Synopsis
        Gets the content of an INI file

    .Description
        Gets the content of an INI file and returns it as a hashtable

    .Notes
        Author        : Oliver Lipkau <oliver@lipkau.net>
        Blog        : http://oliver.lipkau.net/blog/
        Source        : https://github.com/lipkau/PsIni
                      http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91
        Version        : 1.0 - 2010/03/12 - Initial release
                      1.1 - 2014/12/11 - Typo (Thx SLDR)
                                         Typo (Thx Dave Stiff)

        #Requires -Version 2.0

    .Inputs
        System.String

    .Outputs
        System.Collections.Hashtable

    .Parameter FilePath
        Specifies the path to the input file.

    .Parameter Encoding
       Specifies the type of character encoding used in the file. Valid values are "Unicode", "UTF7",
        "UTF8", "UTF32", "ASCII", "BigEndianUnicode", "Default", and "OEM". "UTF8" is the default.
       "Default" uses the encoding of the system's current ANSI code page.
       "OEM" uses the current original equipment manufacturer code page identifier for the operating
       system.

    .Example
        $FileContent = Get-IniContent "C:\myinifile.ini"
        -----------
        Description
        Saves the content of the c:\myinifile.ini in a hashtable called $FileContent

    .Example
        $inifilepath | $FileContent = Get-IniContent
        -----------
        Description
        Gets the content of the ini file passed through the pipe into a hashtable called $FileContent

    .Example
        C:\PS>$FileContent = Get-IniContent "c:\settings.ini"
        C:\PS>$FileContent["Section"]["Key"]
        -----------
        Description
        Returns the key "Key" of the section "Section" from the C:\settings.ini file

    .Link
        Out-IniFile
    #>

    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [ValidateScript( { (Test-Path $_) -and ((Get-Item $_).Extension -eq ".ini") })]
        [Parameter(ValueFromPipeline = $True, Mandatory = $True)]
        [string]$FilePath,

        [ValidateSet("Unicode", "UTF7", "UTF8", "UTF32", "ASCII", "BigEndianUnicode", "Default", "OEM")]
        [Parameter()]
        [string]$Encoding = "UTF8"
    )

    Begin
    { Write-Verbose "$($MyInvocation.MyCommand.Name):: Function started" }

    Process {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Processing file: $Filepath"

        $ini = @{ }
        switch -regex (Get-Content -Path $FilePath -Encoding $Encoding) {
            "^\[(.+)\]$" {
                # Section
                $section = $matches[1]
                $ini[$section] = @{ }
                $CommentCount = 0
            }
            "^(;.*)$" {
                # Comment
                if (!($section)) {
                    $section = "No-Section"
                    $ini[$section] = @{ }
                }
                $value = $matches[1]
                $CommentCount = $CommentCount + 1
                $name = "Comment" + $CommentCount
                $ini[$section][$name] = $value
            }
            "(.+?)\s*=\s*(.*)" {
                # Key
                if (!($section)) {
                    $section = "No-Section"
                    $ini[$section] = @{ }
                }
                $name, $value = $matches[1..2]
                $ini[$section][$name] = $value
            }
        }
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Finished Processing file: $FilePath"
        Return $ini
    }

    End
    { Write-Verbose "$($MyInvocation.MyCommand.Name):: Function ended" }
}

Function Out-IniFile {
    <#
    .Synopsis
        Write hash content to INI file

    .Description
        Write hash content to INI file

    .Notes
        Author        : Oliver Lipkau <oliver@lipkau.net>
        Blog        : http://oliver.lipkau.net/blog/
        Source        : https://github.com/lipkau/PsIni
                      http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91
        Version        : 1.0 - 2010/03/12 - Initial release
                      1.1 - 2012/04/19 - Bugfix/Added example to help (Thx Ingmar Verheij)
                      1.2 - 2014/12/11 - Improved handling for missing output file (Thx SLDR)

        #Requires -Version 2.0

    .Inputs
        System.String
        System.Collections.Hashtable

    .Outputs
        System.IO.FileSystemInfo

    .Parameter Append
        Adds the output to the end of an existing file, instead of replacing the file contents.

    .Parameter InputObject
        Specifies the Hashtable to be written to the file. Enter a variable that contains the objects or type a command or expression that gets the objects.

    .Parameter FilePath
        Specifies the path to the output file.

     .Parameter Encoding
        Specifies the type of character encoding used in the file. Valid values are "Unicode", "UTF7",
         "UTF8", "UTF32", "ASCII", "BigEndianUnicode", "Default", and "OEM". "UTF8" is the default.

        "Default" uses the encoding of the system's current ANSI code page.

        "OEM" uses the current original equipment manufacturer code page identifier for the operating
        system.

     .Parameter Force
        Allows the cmdlet to overwrite an existing read-only file. Even using the Force parameter, the cmdlet cannot override security restrictions.

     .Parameter PassThru
        Passes an object representing the location to the pipeline. By default, this cmdlet does not generate any output.

    .Example
        Out-IniFile $IniVar "C:\myinifile.ini"
        -----------
        Description
        Saves the content of the $IniVar Hashtable to the INI File c:\myinifile.ini

    .Example
        $IniVar | Out-IniFile "C:\myinifile.ini" -Force
        -----------
        Description
        Saves the content of the $IniVar Hashtable to the INI File c:\myinifile.ini and overwrites the file if it is already present

    .Example
        $file = Out-IniFile $IniVar "C:\myinifile.ini" -PassThru
        -----------
        Description
        Saves the content of the $IniVar Hashtable to the INI File c:\myinifile.ini and saves the file into $file

    .Example
        $Category1 = @{"Key1"="Value1";"Key2"="Value2"}
    $Category2 = @{"Key1"="Value1";"Key2"="Value2"}
    $NewINIContent = @{"Category1"=$Category1;"Category2"=$Category2}
    Out-IniFile -InputObject $NewINIContent -FilePath "C:\MyNewFile.INI"
        -----------
        Description
        Creating a custom Hashtable and saving it to C:\MyNewFile.INI
    .Link
        Get-IniContent
    #>

    [CmdletBinding()]
    Param(
        [switch]$Append,

        [ValidateSet("Unicode", "UTF7", "UTF8", "UTF32", "ASCII", "BigEndianUnicode", "Default", "OEM")]
        [Parameter()]
        [string]$Encoding = "UTF8",


        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^([a-zA-Z]\:)?.+\.ini$')]
        [Parameter(Mandatory = $True)]
        [string]$FilePath,

        [switch]$Force,

        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipeline = $True, Mandatory = $True)]
        [Hashtable]$InputObject,

        [switch]$Passthru
    )

    Begin
    { Write-Verbose "$($MyInvocation.MyCommand.Name):: Function started" }

    Process {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Writing to file: $Filepath"

        if ($append) { $outfile = Get-Item $FilePath }
        else { $outFile = New-Item -ItemType file -Path $Filepath -Force:$Force }
        if (!($outFile)) { Throw "Could not create File" }
        foreach ($i in $InputObject.keys) {
            if (!($($InputObject[$i].GetType().Name) -eq "Hashtable")) {
                #No Sections
                Write-Verbose "$($MyInvocation.MyCommand.Name):: Writing key: $i"
                Add-Content -Path $outFile -Value "$i=$($InputObject[$i])" -Encoding $Encoding
            }
            else {
                #Sections
                Write-Verbose "$($MyInvocation.MyCommand.Name):: Writing Section: [$i]"
                Add-Content -Path $outFile -Value "[$i]" -Encoding $Encoding
                Foreach ($j in $($InputObject[$i].keys | Sort-Object)) {
                    if ($j -match "^Comment[\d]+") {
                        Write-Verbose "$($MyInvocation.MyCommand.Name):: Writing comment: $j"
                        Add-Content -Path $outFile -Value "$($InputObject[$i][$j])" -Encoding $Encoding
                    }
                    else {
                        Write-Verbose "$($MyInvocation.MyCommand.Name):: Writing key: $j"
                        Add-Content -Path $outFile -Value "$j=$($InputObject[$i][$j])" -Encoding $Encoding
                    }

                }
                Add-Content -Path $outFile -Value "" -Encoding $Encoding
            }
        }
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Finished Writing to file: $Filepath"
        if ($PassThru) { Return $outFile }
    }

    End
    { Write-Verbose "$($MyInvocation.MyCommand.Name):: Function ended" }
}

$modulesDir = (Join-Path $PSScriptRoot "PsModules")

# Install-ModuleToDirectory -Name psdocker -Destination $modulesDir > $null
# Install-ModuleToDirectory -Name ConvertFrom-Docker -Destination $modulesDir > $null
