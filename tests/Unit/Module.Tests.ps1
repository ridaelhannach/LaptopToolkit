Describe "LaptopToolkit Module Integrity" {
    $manifestPath = "$PSScriptRoot/../../src/LaptopToolkit.psd1"

    It "Has a valid module manifest" {
        Test-Path $manifestPath | Should -BeTrue
        $manifest = Test-ModuleManifest -Path $manifestPath
        $manifest.Name | Should -Be "LaptopToolkit"
        $manifest.Version.ToString() | Should -Be "1.0.0"
    }

    It "Exports all documented public functions" {
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $expected = @(
            'Get-LaptopHealth',
            'Test-SecurityStatus',
            'Test-NetworkDiagnostics',
            'Test-DeveloperEnvironment',
            'Invoke-SafeDiskCleanup',
            'Get-StartupPrograms',
            'New-HealthReport',
            'New-BatteryReport',
            'Register-ToolkitScheduledTask',
            'Start-ToolkitDashboard'
        )

        foreach ($fn in $expected) {
            $manifest.FunctionsToExport | Should -Contain $fn
        }
    }
}
