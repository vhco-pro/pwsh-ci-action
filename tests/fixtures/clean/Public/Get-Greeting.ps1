function Get-Greeting {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Name = 'World'
    )

    "Hello, $Name"
}
