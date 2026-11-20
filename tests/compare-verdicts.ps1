# Fails unless the composite action and ci.ps1 gave the same verdict, and that verdict
# is the one the fixture case expects.
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('success', 'failure')]
    [string]$CompositeOutcome,

    [Parameter(Mandatory = $true)]
    [int]$DirectExit,

    [Parameter(Mandatory = $true)]
    [int]$ExpectExit
)

$composite = if ($CompositeOutcome -eq 'success') { 0 } else { 1 }
$direct = if ($DirectExit -eq 0) { 0 } else { 1 }
if ($composite -ne $direct) {
    throw "the composite action's verdict ($CompositeOutcome) differs from ci.ps1's (exit $DirectExit)"
}
if ($direct -ne $ExpectExit) {
    throw "both runs gave exit $direct; the case expects $ExpectExit"
}
Write-Output "composite and ci.ps1 agree: exit $direct, as expected"
