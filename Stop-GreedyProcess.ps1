<#
.NOTES
    Author: Robert D. Biddle
    Date: Aug/09/2017
.Synopsis
   Kill the process which is utilizing the most CPU time
.DESCRIPTION
    Specify the maximum desired total system CPU utilization along with a maximum CPU utilization allowed for a single process and
    a list of expendable processes (processes you don't mind killing) and a time period in seconds over which to monitor 
.EXAMPLE
   Stop-GreedyProcess -ExpendableProcessList ("chrome","iexplore") -MaxAcceptableSystemProcessorUtilization 75 -MaxAcceptableProcessProcessorUtilization 45 -SecondsToAverage 30
#>
function Stop-GreedyProcess {
    [CmdletBinding(
        SupportsShouldProcess = $false,
        PositionalBinding = $false,
        HelpUri = 'https://github.com/RobBiddle/Stop-GreedyProcess/',
        ConfirmImpact = 'Medium')]
    Param (
        [String[]]$ExpendableProcessList = ("chrome","iexplore"),
        [ValidateRange(50,99)]
        [Int]$MaxAcceptableSystemProcessorUtilization = 90,
        [ValidateRange(10,99)]
        [Int]$MaxAcceptableProcessProcessorUtilization = 50,
        [ValidateRange(1,600)]
        [Int]$SecondsToAverage = 10,
        [String]$EventSource = "MgmtScripts"
    )
    function Get-AvgCPU {
        Param(
            [ValidateRange(1,600)]
            [Int]$TimeInSeconds = 1
        )
        1..$TimeInSeconds | ForEach-Object {
            $SumOfAverage += (Get-WmiObject win32_processor | 
                Measure-Object -property LoadPercentage -Average | 
                    Select-Object Average).Average
        }
        $SumOfAverage / $TimeInSeconds
    }
    function Get-GreediestProcess {
        Get-WmiObject -Class Win32_PerfFormattedData_PerfProc_Process -Filter "NOT Name='Idle' AND NOT Name='_Total'" | 
            Sort-Object PercentProcessorTime -Descending |        
                    Select-Object -first 1
    }

    # Check AVG CPU of system, proceed if above MaxAcceptableSystemProcessorUtilization, exit if below
    $SystemProcessorUtilization = Get-AvgCPU -TimeInSeconds $SecondsToAverage
    If($SystemProcessorUtilization -LT $MaxAcceptableSystemProcessorUtilization){
        New-EventLog -LogName Application -Source $EventSource -ErrorAction SilentlyContinue
        Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventID 1042 -Message "Nothing to do. Total System CPU Utilization of $SystemProcessorUtilization is less than $MaxAcceptableSystemProcessorUtilization"
        Return
    }
    
    # Find Processes using the most CPU time
    $GreediestProcess = Get-GreediestProcess

    # Only continue if GreediestProcess is in ExpendableProcessList
    if (($GreediestProcess.Name -split "#")[0] -notin $ExpendableProcessList) {
        New-EventLog -LogName Application -Source $EventSource -ErrorAction SilentlyContinue
        Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventID 1042 -Message  "Nothing to do. Greediest Process $($GreediestProcess.Name) is not in $ExpendableProcessList"
        Return
    }

    # Only continue if GreediestProcess is using more than MaxAcceptableProcessProcessorUtilization
    If($GreediestProcess.PercentProcessorTime -LT $MaxAcceptableProcessProcessorUtilization){
        New-EventLog -LogName Application -Source $EventSource -ErrorAction SilentlyContinue
        Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventID 1042 -Message  "Nothing to do. Greediest Process CPU Utilization of $($GreediestProcess.PercentProcessorTime) is less than $MaxAcceptableProcessProcessorUtilization"
        Return
    }

    # Identify which user the GreediestProcess belongs to
    $RdsUsers = qwinsta | foreach { ($_.trim() -replace "\s+" , ",") } | ConvertFrom-Csv
    $GreediestProcessInfo = Get-WmiObject -Class Win32_Process | Where-Object ProcessId -eq $GreediestProcess.IDProcess
    $GreediestProcessOwner = ($RdsUsers | Where-Object ID -eq $GreediestProcessInfo.SessionId).USERNAME

    # Kill GreediestProcess
    Stop-Process $GreediestProcess -Force -ErrorAction SilentlyContinue

    # Write to EventLog
    New-EventLog -LogName Application -Source $EventSource -ErrorAction SilentlyContinue
    Write-EventLog -LogName Application -Source $EventSource -EntryType Warning -EventID 187 -Message "Stop-GreedyProcess killed process named: $($GreediestProcess.Name) owned by user: $GreediestProcessOwner" -ErrorAction SilentlyContinue
    Write-Output "Stop-GreedyProcess killed process named: $($GreediestProcess.Name) owned by user: $GreediestProcessOwner"
}
