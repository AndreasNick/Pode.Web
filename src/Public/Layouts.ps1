function New-PodeWebGrid
{
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable[]]
        $Components,

        [switch]
        $Vertical
    )

    return @{
        ComponentType = 'Grid'
        Components = $Components
        Vertical = $Vertical.IsPresent
    }
}

function New-PodeWebTabs
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable[]]
        $Tabs
    )

    return @{
        ComponentType = 'Tabs'
        Tabs = $Tabs
    }
}

function New-PodeWebTab
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $Name,

        [Parameter()]
        [hashtable[]]
        $Components
    )

    return @{
        ComponentType = 'Tab'
        Name = $Name
        Components = $Components
    }
}