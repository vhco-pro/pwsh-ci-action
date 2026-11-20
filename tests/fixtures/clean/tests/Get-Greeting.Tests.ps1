BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'Clean.psm1') -Force
}

Describe 'Get-Greeting' {
    It 'greets the given name' {
        Get-Greeting -Name 'Ada' | Should -Be 'Hello, Ada'
    }
}
