# Script name:   	check_ms_win_tasks.ps1
# Version:			2.14.05.05
# Created on:    	01/02/2014																			
# Author:        	D'Haese Willem
# Purpose:       	Checks Microsoft Windows scheduled tasks excluding defined folders and defined 
#					task patterns, returning state of tasks with name, author, exit code and 
#					performance data to Nagios.
# On Github:		https://github.com/willemdh/check_ms_win_tasks.ps1
# To do:			
#  	- Add switches to change returned values and output
#  	- Add array parameter with exit codes that should be excluded
#	- Make parameters non mandatory
#	- Test remote execution
# History:       	
#	03/02/2014 => Add array as argument with excluded folders
#	15/02/2014 => Add array as argument with excluded task patterns
#	03/03/2014 => Added perfdata and edited output
#	09/03/2014 => Added running tasks information and perfdata
#	22/03/2014 => Resolved a bug with output treated as perfdata
#	23/03/2014 => Created repository on Github and updated documentation
#	11/04/2014 => New output format with outputstring to be able to see failed tasks in service history
#	11/04/2014 => Added [int] to prevent decimal numbers
#	24/04/2014 => After testing multiple possibilities with `r`n and <br>, decided to not go multiline at all and used ' -> ' to split failed and running tasks
# 	05/05/2014 => Test script fro better handling and checking of parameters, does not work yet...
# How to:
#	1) Put the script in the NSCP scripts folder
#	2) In the nsclient.ini configuration file, define the script like this:
#		check_ms_win_tasks=cmd /c echo scripts\check_ms_win_tasks.ps1 $ARG1$ $ARG2$ $ARG3$; exit 
#		$LastExitCode | powershell.exe -command -
#	3) Make a command in Nagios like this:
#		check_ms_win_tasks => $USER1$/check_nrpe -H $HOSTADDRESS$ -p 5666 -t 60 -c 
#		check_ms_win_tasks -a $ARG1$ $ARG2$ $ARG3$
#	4) Configure your service in Nagios:
#		- Make use of the above created command
#		- Parameter 1 should be 'localhost' (did not test with remoting)
#		- Parameter 2 should be an array of folders to exclude, example 'Microsoft, Backup'
#		- Parameter 3 should be an array of task patterns to exclude, example 'Jeff,"Copy Test"'
#		- All single quotes need to be included (In Nagios XI)
#		- Array values with spaces need double quotes (see above example)
#		- All three parameters are mandatory for now, use " " if you don't want exclusions
# Help:
#	This script works perfectly in our environment on Windows 2008 and Windows 2008 R2 servers. If
#	you do happen to find an issue, let me know on Github. The script is highly adaptable if you 
#	want different output etc. I've been asked a few times to make it multilingual, as obviously
#	this script will only work on English Windows 2008 or higher servers, but as I do not have 
#	non-English servers at my disposal, I'm not going to implement any other languages..
# Copyright:
#	This program is free software: you can redistribute it and/or modify it under the terms of the
# 	GNU General Public License as published by the Free Software Foundation, either version 3 of 
#   the License, or (at your option) any later version.
#   This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; 
#	without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
# 	See the GNU General Public License for more details.You should have received a copy of the GNU
#   General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.


#param(
#	[Parameter(Mandatory=$true)][string]$ComputerName = "localhost",
#    [Parameter(Mandatory=$true)]$ExclFolders = @(),
#	[Parameter(Mandatory=$true)]$ExclTasks = @(),
#	[switch]$RootFolder
#)

[String]$DefaultString = "ABCD123"
[Int]$DefaultInt = -99

$TaskStruct = @{}
    [string]$TaskStruct.Hostname = ""
    [string[]]$TaskStruct.ExclFolders = @()
    [string[]]$TaskStruct.ExclTasks = @()
    [int]$TaskStruct.Time = "1"
    [Int]$TaskStruct.ExitCode = 3
    [String]$TaskStruct.OutputString = "Critical: There was an error processing performance counter data"
    [String]$TaskStruct.OkString = $DefaultString
    [String]$TaskStruct.WarnString = $DefaultString
    [String]$TaskStruct.CritString = $DefaultString
    [Int]$TaskStruct.WarnHigh = $DefaultInt
    [Int]$TaskStruct.CritHigh = $DefaultInt
    [Int]$TaskStruct.WarnLow = $DefaultInt
    [Int]$TaskStruct.CritLow = $DefaultInt
    $TaskStruct.Result 
 
#region Functions

Function Process-Args {
    Param ( 
        [Parameter(Mandatory=$True)]$Args,
        [Parameter(Mandatory=$True)]$Return
    )

        If ( $Args.Count -lt 2 ) {
            Write-Help
        }

        For ( $i = 0; $i -lt $Args.count-1; $i++ ) {
            
            $CurrentArg = $Args[$i].ToString()
            $Value = $Args[$i+1]

                If ($CurrentArg -cmatch "-H") {
                    If (Check-Strings $Value) {
                        $Return.Hostname = $Value  
                    }
                }
                ElseIf ($CurrentArg -match "--Hostname") {
                    If (Check-Strings $Value) {
                        $Return.Hostname = $Value
                    }
                }
                ElseIf ($CurrentArg -cmatch "-EF") { 
                    If ($Value) {
                        $Return.ExclFolders = $Value
                    }
                }
                ElseIf ($CurrentArg -match "--Excl-Folders") { 
                ElseIf (Check-Strings $Value) {
                        $Return.ExclFolders = $Value
                    }
                }
                ElseIf ($CurrentArg -cmatch "-ET") {
                    If (Check-Strings $Value) {
                        $Return.ExclTasks = $Value
                    }
                }
                ElseIf ($CurrentArg -match "--Excl-Tasks") {
                    If (Check-Strings $Value) {
                        $Return.ExclTasks = $Value
                    }
                }
                ElseIf ($CurrentArg -cmatch "-h") { Write-Help }
                ElseIf ($CurrentArg -match "--help") { Write-Help }

        } # End for loop

    Return $Return

}

# Function to check strings for invalid and potentially malicious chars

Function Check-Strings {

    Param ( [Parameter(Mandatory=$True)][string]$String )

    # `, `n, |, ; are bad, I think we can leave {}, @, and $ at this point.
    $BadChars=@("``", "|", ";", "`n")

    $BadChars | ForEach-Object {

        If ( $String.Contains("$_") ) {
            Write-Host "Unknown: String contains illegal characters."
            Exit 3
        }

    } # end for

    Return $true
} 

# Function to get all task subfolders

function Get-AllTaskSubFolders {
    [cmdletbinding()]
    param (
       $FolderRef = $Schedule.getfolder("\")
    )
    if ($RootFolder) {
        $FolderRef
    } else {
        $FolderRef	     
        if(($folders = $folderRef.getfolders(1)).count -ge 1) {
            foreach ($folder in $folders) {
				if ($ExclFolders -notcontains $folder.Name) {     
                	if(($folder.getfolders(1).count -ge 1)) {
                    	Get-AllTaskSubFolders -FolderRef $folder
                	}
					else {
						$folder
					}
				}
            }
        }
    }
}

# Function to check a string for patterns

function Check-Array ([string]$str, [string[]]$patterns) {
    foreach($pattern in $patterns) { if($str -match $pattern) { return $true; } }
    return $false;
}

# Function to write help output

Function Write-Help {
    Write-Output "check_ms_win_tasks.ps1:`n`tThis script is designed to check Windows 2008 or higher scheduled tasks and alert in case tasks failed in Nagios style output."
    Write-Output "Arguments:"
    write-output "`t-H | --Hostname ) Optional hostname of remote system."
    Write-Output "`t-n | --Counter-Name) Name of performance counter to collect."
    Write-Output "`t-l | --Label) Name of label for counters, opposed to Counter[n], in output message"
    Write-Output "`t-t | --Time ) Time in seconds for sample interval."
    Write-Output "`t-w | --Warning ) Warning string or number to check against. Somewhat matches plugins threshold guidelines"
    Write-Output "`t-c | --Critial ) Critical string or number to check against. Somewhat matches plugins threshold guidelines"
    Write-Output "`t-h | --Help ) Print this help output."
} 

#endregion Functions

# Main function to kick off functionality

Function Check-MS-Win-Tasks {

 	Param ( 
        [Parameter(Mandatory=$True)]$Args,
        [Parameter(Mandatory=$True)]$TaskStruct
     )
	 
	# Process arguments and insert into task struct
    $TaskStruct = Process-Args $Args $CounterStruct

	if ($PSVersionTable) {$Host.Runspace.ThreadOptions = 'ReuseThread'}
 
	$status = 3;
 
	try {
		$schedule = new-object -com("Schedule.Service") 
	} 
	catch {
		Write-Host "Schedule.Service COM Object not found, this script requires this object"
		exit $status
		return
	} 

	$Schedule.connect($ComputerName) 
	$AllFolders = @()
	$AllFolders = Get-AllTaskSubFolders
	[int]$TaskOk = 0
	[int]$TaskNotOk = 0
	[int]$TaskRunning = 0
	[int]$TotalTasks = 0
	$BadTasks = @()
	$GoodTasks = @()
	$RunningTasks = @()
	$OutputString = ""


	foreach ($Folder in $AllFolders) {		
			    if (($Tasks = $Folder.GetTasks(0))) {
			        $Tasks | Foreach-Object {$ObjTask = New-Object -TypeName PSCustomObject -Property @{
				            'Name' = $_.name
			                'Path' = $_.path
			                'State' = $_.state
			                'Enabled' = $_.enabled
			                'LastRunTime' = $_.lastruntime
			                'LastTaskResult' = $_.lasttaskresult
			                'NumberOfMissedRuns' = $_.numberofmissedruns
			                'NextRunTime' = $_.nextruntime
			                'Author' =  ([xml]$_.xml).Task.RegistrationInfo.Author
			                'UserId' = ([xml]$_.xml).Task.Principals.Principal.UserID
			                'Description' = ([xml]$_.xml).Task.RegistrationInfo.Description
							'Cmd' = ([xml]$_.xml).Task.Actions.Exec.Command 
							'Params' = ([xml]$_.xml).Task.Actions.Exec.Arguments
			            }
					if ($ObjTask.LastTaskResult -eq "0") {
						if(!(Check-Array $ObjTask.Name $ExclTasks)){
							$GoodTasks += $ObjTask
							$TaskOk += 1
							}
						}
					elseif ($ObjTask.LastTaskResult -eq "0x00041301") {
						if(!(Check-Array $ObjTask.Name $ExclTasks)){
							$RunningTasks += $ObjTask
							$TaskRunning += 1
							}
						}
					else {
						if(!(Check-Array $ObjTask.Name $ExclTasks)){
							$BadTasks += $ObjTask
							$TaskNotOk += 1
							}
						}
					}
			    }	
	} 
	$TotalTasks = $TaskOk + $TaskNotOk + $TaskRunning
	if ($TaskNotOk -gt "0") {
		$OutputString += "$TaskNotOk / $TotalTasks tasks failed! Check tasks: "
		foreach ($BadTask in $BadTasks) {
			$OutputString += " -> Task $($BadTask.Name) by $($BadTask.Author) failed with exitcode $($BadTask.lasttaskresult) "
		}
		foreach ($RunningTask in $RunningTasks) {
			$OutputString += " -> Task $($RunningTask.Name) by $($RunningTask.Author), exitcode $($RunningTask.lasttaskresult) is still running! "
		}
		$OutputString +=  " | 'Total Tasks'=$TotalTasks, 'OK Tasks'=$TaskOk, 'Failed Tasks'=$TaskNotOk, 'Running Tasks'=$TaskRunning"
		$status = 2
	}	
	else {
		$OutputString +=  "All $TotalTasks tasks ran succesfully! "
		foreach ($RunningTask in $RunningTasks) {
			$OutputString +=  " -> Task $($RunningTask.Name) by $($RunningTask.Author), exitcode $($RunningTask.lasttaskresult) is still running! "
		}
		$OutputString +=  " | 'Total Tasks'=$TotalTasks, 'OK Tasks'=$TaskOk, 'Failed Tasks'=$TaskNotOk, 'Running Tasks'=$TaskRunning"
		$status = 0
	}
	Write-Host "$outputString"
	exit $status

}

# Execute main block

Check-MS-Win-Tasks $Args $TaskStruct