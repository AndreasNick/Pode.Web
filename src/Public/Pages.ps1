function Set-PodeWebLoginPage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $Authentication,

        [Parameter()]
        [string]
        $Icon,

        [Parameter()]
        [string]
        $Copyright,

        [Parameter()]
        [string]
        $UsernameProperty,

        [Parameter()]
        [string]
        $GroupProperty
    )

    Set-PodeWebState -Name 'auth' -Value $Authentication
    Set-PodeWebState -Name 'auth-username-prop' -Value $UsernameProperty
    Set-PodeWebState -Name 'auth-group-prop' -Value $GroupProperty

    if ([string]::IsNullOrWhiteSpace($Icon)) {
        $Icon = '/pode.web/images/icon.png'
    }

    $auth = Get-PodeAuth -Name $Authentication
    $auth.Failure.Url = '/login'
    $auth.Success.Url = '/'

    Add-PodeRoute -Method Get -Path '/login' -Authentication $Authentication -Login -ScriptBlock {
        Write-PodeWebViewResponse -Path 'login' -Data @{
            Icon = $using:Icon
            Copyright = $using:Copyright
        }
    }

    Add-PodeRoute -Method Post -Path '/login' -Authentication $Authentication -Login
    Add-PodeRoute -Method Post -Path '/logout' -Authentication $Authentication -Logout

    Remove-PodeRoute -Method Get -Path '/'
    Add-PodeRoute -Method Get -Path '/' -Authentication $Authentication -ScriptBlock {
        $pages = @(Get-PodeWebState -Name 'pages')
        if (($null -ne $pages) -and ($pages.Length -gt 0)) {
            Move-PodeResponseUrl -Url "/pages/$($pages[0].Name)"
            return
        }

        $authData = Get-PodeWebAuthData
        $username = Get-PodeWebAuthUsername -AuthData $authData
        $groups = Get-PodeWebAuthGroups -AuthData $authData

        Write-PodeWebViewResponse -Path 'index' -Data @{
            Page = @{
                Name = 'Home'
            }
            Auth = @{
                Enabled = $true
                Authenticated = $authData.IsAuthenticated
                Username = $username
                Groups = $groups
            }
        }
    }
}

function Set-PodeWebHomePage
{
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable[]]
        $Components,

        [Parameter()]
        [string]
        $Title,

        [Parameter()]
        [Alias('NoAuth')]
        [switch]
        $NoAuthentication
    )

    # ensure components are correct
    foreach ($component in $Components) {
        if ([string]::IsNullOrWhiteSpace($component.ComponentType)) {
            throw "Invalid component supplied: $($component)"
        }
    }

    $auth = $null
    if (!$NoAuthentication) {
        $auth = (Get-PodeWebState -Name 'auth')
    }

    if ([string]::IsNullOrWhiteSpace($Title)) {
        $Title = 'Home'
    }

    Remove-PodeRoute -Method Get -Path '/'

    Add-PodeRoute -Method Get -Path '/' -Authentication $auth -ScriptBlock {
        $comps = $using:Components
        if (($null -eq $comps) -or ($comps.Length -eq 0)) {
            $pages = @(Get-PodeWebState -Name 'pages')
            if (($null -ne $pages) -and ($pages.Length -gt 0)) {
                Move-PodeResponseUrl -Url "/pages/$($pages[0].Name)"
                return
            }
        }

        $authData = Get-PodeWebAuthData
        $username = Get-PodeWebAuthUsername -AuthData $authData
        $groups = Get-PodeWebAuthGroups -AuthData $authData

        Write-PodeWebViewResponse -Path 'index' -Data @{
            Page = @{
                Name = 'Home'
            }
            Title = $using:Title
            Components = $comps
            Auth = @{
                Enabled = ![string]::IsNullOrWhiteSpace((Get-PodeWebState -Name 'auth'))
                Authenticated = $authData.IsAuthenticated
                Username = $username
                Groups = $groups
            }
        }
    }
}

function Add-PodeWebPage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $Name,

        [Parameter()]
        [string]
        $Title,

        [Parameter()]
        [string]
        $Group,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Icon = 'file',

        [Parameter()]
        [hashtable[]]
        $Components,

        [Parameter()]
        [scriptblock]
        $ScriptBlock,

        [Parameter()]
        [string[]]
        $AccessGroups = @(),

        [Parameter()]
        [string[]]
        $AccessUsers = @(),

        [Parameter()]
        [Alias('NoAuth')]
        [switch]
        $NoAuthentication
    )

    # ensure components are correct
    foreach ($component in $Components) {
        if ([string]::IsNullOrWhiteSpace($component.ComponentType)) {
            throw "Invalid component supplied: $($component)"
        }
    }

    # test if page exists
    if (Test-PodeWebPage -Name $Name) {
        throw " Web page already exists: $($Name)"
    }

    $pageMeta = @{
        Name = $Name
        Icon = $Icon
        Group = $Group
        Access = @{
            Groups = @($AccessGroups)
            Users = @($AccessUsers)
        }
    }

    Set-PodeWebState -Name 'pages' -Value  (@(Get-PodeWebState -Name 'pages') + $pageMeta)

    # set page title
    if ([string]::IsNullOrWhiteSpace($Title)) {
        $Title = $Name
    }

    # does the page need auth?
    $auth = $null
    if (!$NoAuthentication) {
        $auth = (Get-PodeWebState -Name 'auth')
    }

    # add the page route
    Add-PodeRoute -Method Get -Path "/pages/$($Name)" -Authentication $auth -ScriptBlock {
        $global:PageData = $using:pageMeta
        $global:PageData.ShowBack = (($null -ne $WebEvent.Query) -and ($WebEvent.Query.Count -gt 0))

        # get auth details of a user
        $authData = Get-PodeWebAuthData
        $username = Get-PodeWebAuthUsername -AuthData $authData
        $groups = Get-PodeWebAuthGroups -AuthData $authData

        $authMeta = @{
            Enabled = ![string]::IsNullOrWhiteSpace((Get-PodeWebState -Name 'auth'))
            Authenticated = $authData.IsAuthenticated
            Username = $username
            Groups = $groups
        }

        # check access - 403 if denied
        if (!(Test-PodeWebPageAccess -PageAccess $global:PageData.Access -Auth $authMeta)) {
            Set-PodeResponseStatus -Code 403
        }

        else {
            # if we have a scriptblock, invoke that to get dynamic components
            $comps =$null
            if ($null -ne $using:ScriptBlock) {
                $comps = Invoke-PodeScriptBlock -ScriptBlock $using:ScriptBlock -Return
            }

            if (($null -eq $comps) -or ($comps.Length -eq 0)) {
                $comps = $using:Components
            }

            Write-PodeWebViewResponse -Path 'index' -Data @{
                Page = $global:PageData
                Title = $using:Title
                Components = $comps
                Auth = $authMeta
            }
        }

        $global:PageData = $null
    }
}

function ConvertTo-PodeWebPage
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [string[]]
        $Commands,

        [Parameter()]
        [string]
        $Module,

        [switch]
        $GroupVerbs,

        [Parameter()]
        [Alias('NoAuth')]
        [switch]
        $NoAuthentication
    )

    # if a module was supplied, import it - then validate the commands
    if (![string]::IsNullOrWhiteSpace($Module)) {
        Import-PodeModule -Name $Module

        Write-Verbose "Getting exported commands from module"
        $ModuleCommands = (Get-Module -Name $Module | Sort-Object -Descending | Select-Object -First 1).ExportedCommands.Keys

        # if commands were supplied validate them - otherwise use all exported ones
        if (Test-PodeIsEmpty $Commands) {
            Write-Verbose "Using all commands in $($Module) for converting to Pages"
            $Commands = $ModuleCommands
        }
        else {
            Write-Verbose "Validating supplied commands against module's exported commands"
            foreach ($cmd in $Commands) {
                if ($ModuleCommands -inotcontains $cmd) {
                    throw "Module $($Module) does not contain function $($cmd) to convert to a Page"
                }
            }
        }
    }

    # if there are no commands, fail
    if (Test-PodeIsEmpty $Commands) {
        throw 'No commands supplied to convert to Pages'
    }

    $sysParams = @(
        'Verbose',
        'Debug',
        'ErrorAction',
        'WarningAction',
        'InformationAction',
        'ErrorVariable',
        'WarningVariable',
        'InformationVariable',
        'OutVariable',
        'OutBuffer',
        'PipelineVariable'
    )
    
    # create the pages for each of the commands
    foreach ($cmd in $Commands) {
        $cmdInfo = (Get-Command -Name $cmd -ErrorAction Stop)

        $sets = $cmdInfo.ParameterSets
        if (($null -eq $sets) -or ($sets.Length -eq 0)) {
            continue
        }

        $ast = $cmdInfo.ScriptBlock.Ast
        $paramDefs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true)

        $tabs = New-PodeWebTabs -Tabs @(foreach ($set in $sets) {
            $elements = @(foreach ($param in $set.Parameters) {
                if ($sysParams -icontains $param.Name) {
                    continue
                }

                $type = $param.ParameterType.Name
                $default = ($paramDefs | Where-Object { $_.DefaultValue -and $_.Name.Extent.Text -ieq "`$$($param.Name)" }).DefaultValue.Value

                if ($type -iin @('boolean', 'switchparameter')) {
                    New-PodeWebCheckbox -Name $param.Name -AsSwitch
                }
                else {
                    switch ($type) {
                        'pscredential' {
                            New-PodeWebCredential -Name $param.Name
                        }

                        default {
                            $multiple = $param.ParameterType.Name.EndsWith('[]')

                            if ($param.Attributes.TypeId.Name -icontains 'ValidateSetAttribute') {
                                $values = ($param.Attributes | Where-Object { $_.TypeId.Name -ieq 'ValidateSetAttribute' }).ValidValues
                                New-PodeWebSelect -Name  $param.Name -Options $values -SelectedValue $default -Multiple:$multiple
                            }
                            elseif ($param.ParameterType.BaseType.Name -ieq 'enum') {
                                $values = [enum]::GetValues($param.ParameterType)
                                New-PodeWebSelect -Name  $param.Name -Options $values -SelectedValue $default -Multiple:$multiple
                            }
                            else {
                                New-PodeWebTextbox -Name $param.Name -Value $default
                            }
                        }
                    }
                }
            })

            $elements += (New-PodeWebHidden -Name '_Function_Name_' -Value $cmd)

            $name = $set.Name
            if ([string]::IsNullOrWhiteSpace($name) -or ($set.Name -iin @('__AllParameterSets'))) {
                $name = 'Default'
            }

            $formId = "form_param_$($cmd)_$($name)"

            $form = New-PodeWebForm -Name Parameters -Id $formId -NoHeader -Elements $elements -NoAuthentication:$NoAuthentication -ScriptBlock {
                $cmd = $WebEvent.Data['_Function_Name_']
                $WebEvent.Data.Remove('_Function_Name_')

                $_args = @{}
                foreach ($key in $WebEvent.Data.Keys) {
                    if ($key -imatch '(?<name>.+)_(Username|Password)$') {
                        $name = $Matches['name']
                        $uKey = "$($name)_Username"
                        $pKey = "$($name)_Password"

                        if (![string]::IsNullOrWhiteSpace($WebEvent.Data[$uKey]) -and ![string]::IsNullOrWhiteSpace($WebEvent.Data[$pKey])) {
                            $creds = (New-Object System.Management.Automation.PSCredential -ArgumentList $WebEvent.Data[$uKey], (ConvertTo-SecureString -AsPlainText $WebEvent.Data[$pKey] -Force))
                            $_args[$name] = $creds
                        }
                    }
                    else {
                        if ($WebEvent.Data[$key] -iin @('true', 'false')) {
                            $_args[$key] = ($WebEvent.Data[$key] -ieq 'true')
                        }
                        else {
                            if ($WebEvent.Data[$key].Contains(',')) {
                                $_args[$key] = ($WebEvent.Data[$key] -isplit ',' | ForEach-Object { $_.Trim() })
                            }
                            else {
                                $_args[$key] = $WebEvent.Data[$key]
                            }
                        }
                    }
                }

                try {
                    (. $cmd @_args) | Out-PodeWebTextbox -Multiline -Preformat
                }
                catch {
                    $_.Exception | Out-PodeWebTextbox -Multiline -Preformat
                }
            }

            New-PodeWebTab -Name $name -Components $form
        })

        $group = [string]::Empty
        if ($GroupVerbs) {
            $group = $cmdInfo.Verb
            if ([string]::IsNullOrWhiteSpace($group)) {
                $group = '_'
            }
        }

        Add-PodeWebPage -Name $cmd -Icon Settings -Components $tabs -Group $group -NoAuthentication:$NoAuthentication
    }
}