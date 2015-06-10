# Script name:   	check_ms_win_tasks.ps1
# Version:			v4.6.4
# Created on:    	01/02/2014																			
# Author:        	D'Haese Willem
# Purpose:       	Checks Microsoft Windows enabled scheduled tasks excluding defined folders and task patterns, returning state of tasks
#					with name, author, exit code and performance data to Nagios.
# On Github:			https://github.com/willemdh/check_ms_win_tasks
# On OutsideIT:		http://outsideit.net/check-ms-win-tasks
# Recent History:       	
#	07/12/2014 => Cleanup code and updated documentation
#	10/01/2015 => Added hostname checks in argument processing
#   09/03/2015 => Cleanup script following ISESteroids recommendations
#	20/04/2015 => Added script runtime duration and last runtime for failed tasks
#	04/06/2015 => New output with style {Task1(Info1)(Info2)} {Task2(Info1)(Info2)}
# Copyright:
#	This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published
#	by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program is distributed 
#	in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
#	PARTICULAR PURPOSE. See the GNU General Public License for more details. You should have received a copy of the GNU General Public 
#	License along with this program.  If not, see <http://www.gnu.org/licenses/>.

#Requires –Version 2.0

$TaskStruct = New-Object PSObject -Property @{
    Hostname = [string]'localhost';
    ExclFolders = [string[]]@();
    ExclTasks = [string[]]@();
    InclTasks = [string[]]@();
    FolderRef = [string]'';
	AllValidFolders = [string[]]@();
    ExitCode = [int]3;
	TasksOk = [int]0;
	TasksNotOk = [int]0;
	TasksRunning = [int]0;
	TasksTotal = [int]0;
	TasksDisabled = [int]0;
    OutputString = [string]'UNKNOWN: Error processing, no data returned.'
}
	
#region Functions

Function Initialize-Args {
    Param ( 
        [Parameter(Mandatory=$True)]$Args
    )
	
    try {
        For ( $i = 0; $i -lt $Args.count; $i++ ) { 
		    $CurrentArg = $Args[$i].ToString()
            if ($i -lt $Args.Count-1) {
				$Value = $Args[$i+1];
				If ($Value.Count -ge 2) {
					foreach ($Item in $Value) {
						Test-Strings $Item | Out-Null
					}
				}
				else {
	                $Value = $Args[$i+1];
					Test-Strings $Value | Out-Null
				}	                             
            } else {
                $Value = ''
            };

            switch -regex -casesensitive ($CurrentArg) {
                "^(-H|--Hostname)$" {
					if ($Value -ne ([System.Net.Dns]::GetHostByName((hostname.exe)).HostName).tolower() -and $Value -ne 'localhost') {
						& ping.exe -n 1 $Value | out-null
						if($? -eq $true) {			
							$TaskStruct.Hostname = $Value
							$i++						
		    			} 
						else {
		    				Write-Host "CRITICAL: Ping to $Value failed! Please provide valid reachable hostname."
							exit 3
		    			}
					}
					else {
						$TaskStruct.Hostname = $Value
						$i++
					}
						
                }
				"^(-EF|--Excl-Folders)$" {
					If ($Value.Count -ge 2) {
						foreach ($Item in $Value) {
		                		$TaskStruct.ExclFolders+=$Item
		            		}
					}					
					else {
		                $TaskStruct.ExclFolders = $Value  
					}	
                    $i++
                }	
				"^(-ET|--Excl-Tasks)$" {
					If ($Value.Count -ge 2) {
						foreach ($Item in $Value) {
		                		$TaskStruct.ExclTasks+=$Item
		            		}
					}					
					else {
		                $TaskStruct.ExclTasks = $Value  
					}	
                    $i++
                }
				"^(-IT|--Incl-Tasks)$" {
					If ($Value.Count -ge 2) {
						foreach ($Item in $Value) {
		                		$TaskStruct.InclTasks+=$Item
		            		}
					}					
					else {
		                $TaskStruct.InclTasks = $Value  
					}	
                    $i++
                }
                "^(-w|--Warning)$" {
                    if (($value -match "^[\d]+$") -and ([int]$value -lt 100)) {
                        $TaskStruct.WarningTreshold = $value
                    } else {
                        throw "Warning treshold should be numeric and less than 100. Value given is $value."
                    }
                    $i++
                }
                "^(-c|--Critical)$" {
                    if (($value -match "^[\d]+$") -and ([int]$value -lt 100)) {
                        $TaskStruct.CriticalTreshold = $value
                    } else {
                        throw "Critical treshold should be numeric and less than 100. Value given is $value."
                    }
                    $i++
                 }
                "^(-h|--Help)$" {
                    Write-Help
                }
                default {
                    throw "Illegal arguments detected: $_"
                 }
            }
        }
    } catch {
		Write-Host "UNKNOWN: $_"
        Exit $TaskStruct.ExitCode
	}	
}

# Function to check strings for invalid and potentially malicious chars

Function Test-Strings {
    Param ( [Parameter(Mandatory=$True)][string]$String )
    # `, `n, |, ; are bad, I think we can leave {}, @, and $ at this point.
    $BadChars=@("``", '|', ';', "`n")
    $BadChars | ForEach-Object {
        If ( $String.Contains("$_") ) {
            Write-Host 'Unknown: String contains illegal characters.'
            Exit $TaskStruct.ExitCode
        }
    }
    Return $true
} 

function Get-AllTaskSubFolders {
    if ($RootFolder) {
        $TaskStruct.AllValidFolders+=$TaskStruct.FolderRef
		return
    } 
	else {
        $TaskStruct.AllValidFolders+=$TaskStruct.FolderRef	     
        if(($folders = $TaskStruct.FolderRef.getfolders(1)).count -ge 1) {
            foreach ($folder in $folders) {
				if ($TaskStruct.ExclFolders -notcontains $folder.Name) {     
                	if(($folder.getfolders(1).count -ge 1)) {
						$TaskStruct.FolderRef=$folder
                    	Get-AllTaskSubFolders
                	}
					else {
							$TaskStruct.AllValidFolders+=$folder
					}							
				}
			}
			return
        }
    }
	return
}

function Compare-Array  {
    param(
        [System.String]$str,
        [System.String[]]$patterns
         )

    foreach($pattern in $patterns) { 
		if($str -match $pattern) {
			return $true; 
		} 
	}
    return $false;
}

Function Write-Help {
	Write-Host @"
check_ms_win_tasks.ps1:
This script is designed to check check Windows 2008 or higher scheduled tasks and alert in case tasks failed in Nagios style output.
Arguments:
    -H  | --Hostname     => Optional hostname of remote system, default is localhost, not yet tested on remote host.
    -EF | --Excl-Folders => Name of folders to exclude from monitoring.
    -ET | --Excl-Tasks   => Name of task patterns to exclude from monitoring.
    -IT | --Incl-Tasks	 => Only included passed tasks
    -h  | --Help         => Print this help output.
"@
    Exit $TaskStruct.ExitCode;
} 

Function Search-Tasks { 
	try {
		$schedule = new-object -com('Schedule.Service') 
	} 
	catch {
		Write-Host 'UNKNWON: Schedule.Service COM Object not found, this script requires this object.'
		Exit $TaskStruct.ExitCode
	} 
	$Schedule.connect($TaskStruct.Hostname) 
	$TaskStruct.FolderRef = $Schedule.getfolder('\')
	Get-AllTaskSubFolders
	$BadTasks = @()
	$GoodTasks = @()
	$RunningTasks = @()
	$DisabledTasks = @()
	$OutputString = ''
	foreach ($Folder in $TaskStruct.AllValidFolders) {		
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
				if ($ObjTask.LastTaskResult -eq '0' -and $ObjTask.Enabled) {
					if(!(Compare-Array $ObjTask.Name $TaskStruct.ExclTasks)){
						$GoodTasks += $ObjTask
						$TaskStruct.TasksOk += 1
						}
					}
				elseif ($ObjTask.LastTaskResult -eq '0x00041301' -and $ObjTask.Enabled) {
					if(!(Compare-Array $ObjTask.Name $TaskStruct.ExclTasks)){
						$RunningTasks += $ObjTask
						$TaskStruct.TasksRunning += 1
						}
					}
				elseif ($ObjTask.Enabled) {
					if(!(Compare-Array $ObjTask.Name $TaskStruct.ExclTasks)){
						$BadTasks += $ObjTask
						$TaskStruct.TasksNotOk += 1
						}
					}
				else {
					if(!(Compare-Array $ObjTask.Name $TaskStruct.ExclTasks)){
						$DisabledTasks += $ObjTask
						$TaskStruct.TasksDisabled += 1
					}
				}
		    }
		}
	} 
	$TaskStruct.TasksTotal = $TaskStruct.TasksOk + $TaskStruct.TasksNotOk + $TaskStruct.TasksRunning
	if ($TaskStruct.TasksNotOk -gt '0') {
		$OutputString += "$($TaskStruct.TasksNotOk) / $($TaskStruct.TasksTotal) tasks failed! "
		foreach ($BadTask in $BadTasks) {
			$OutputString += "{Taskname: `"$($BadTask.Name)`" (Author: $($BadTask.Author))(Exitcode: $($BadTask.lasttaskresult))(Last runtime: $($BadTask.lastruntime))} "
		}
		if ($TaskStruct.TasksRunning -gt '0') {
			$OutputString += "$($TaskStruct.TasksRunning) / $($TaskStruct.TasksTotal) tasks still running! "
			foreach ($RunningTask in $RunningTasks) {
				$OutputString += "{Taskname: `"$($BadTask.Name)`" (Author: $($BadTask.Author))(Exitcode: $($BadTask.lasttaskresult))(Last runtime: $($BadTask.lastruntime))} "
			}
		}
		$OutputString +=  " | 'Total Tasks'=$($TaskStruct.TasksTotal), 'OK Tasks'=$($TaskStruct.TasksOk), 'Failed Tasks'=$($TaskStruct.TasksNotOk), 'Running Tasks'=$($TaskStruct.TasksRunning)"
		
		$TaskStruct.ExitCode = 2
	}	
	else {
		$OutputString +=  "$($TaskStruct.TasksOk) / $($TaskStruct.TasksTotal) tasks ran succesfully. "
		if ($TaskStruct.TasksRunning -gt '0') {
			$OutputString += "$($TaskStruct.TasksRunning) / $($TaskStruct.TasksTotal) tasks still running! "
			foreach ($RunningTask in $RunningTasks) {
				$OutputString += "{Taskname: `"$($BadTask.Name)`" (Author: $($BadTask.Author))(Exitcode: $($BadTask.lasttaskresult))(Last runtime: $($BadTask.lastruntime))} "
			}
		}
		$OutputString +=  " | 'Total Tasks'=$($TaskStruct.TasksTotal), 'OK Tasks'=$($TaskStruct.TasksOk), 'Failed Tasks'=$($TaskStruct.TasksNotOk), 'Running Tasks'=$($TaskStruct.TasksRunning)"
		$TaskStruct.ExitCode = 0
	}
	Write-Host $outputString
	exit $TaskStruct.ExitCode
}

#endregion Functions

# Main
$StartTime = (Get-Date)
if($Args.count -ge 1){Initialize-Args $Args}
Search-Tasks
Write-Host 'UNKNOWN: Script exited in an abnormal way after running for $([Math]::Round($(((Get-Date)-$StartTime).totalseconds), 2)) seconds. Please debug...'
exit $TaskStruct.ExitCode