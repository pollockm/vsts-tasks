function Invoke-ActionWithRetries
{
    [CmdletBinding()]
    param(
        [scriptblock]
        $Action,

        # ResultRetryEvaluator delegate will be called when Action has been successfully executed. The delegate can check whether result is acceptable or further re-try should be performed
        [scriptblock]
        $ResultRetryEvaluator = { $false },

        # ExceptionRetryEvaluator delegate will be called when Action throws retryable exception. The delegate can check whether exception is acceptable or further re-try should be performed
        [scriptblock]
        $ExceptionRetryEvaluator = { $true },

        [int32]
        $MaxTries = 10,

        [int32]
        $RetryIntervalInSeconds = 1,

        [string[]]
        [ValidateScript( {[System.Exception].IsAssignableFrom([type]$_)})]
        $RetryableExceptions,

        [string]
        $RetryMessage
    )

    Trace-VstsEnteringInvocation $MyInvocation

    if (!$RetryMessage)
    {
        $RetryMessage = Get-VstsLocString -Key RetryAfterMessage $RetryIntervalInSeconds
    }

    $retryIteration = 1
    do
    {
        $result = $false
        $exception = $null

        try
        {
            $result = & $Action
        }
        catch
        {
            if (($null -eq $RetryableExceptions) -or (Test-RetryableException -Exception $_.Exception -RetryableExceptions $RetryableExceptions))
            {
                $shouldRetry = $ExceptionRetryEvaluator.Invoke($_.Exception)
                if (!$shouldRetry)
                {
                    return
                }

                $exception = $_.Exception
                Write-Host (Get-VstsLocString -Key ActionException -ArgumentList $exception.GetType().FullName)
            }
            else
            {
                throw
            }
        }

        if (!$exception -and (!$result -or !$ResultRetryEvaluator.Invoke($result)))
        {
            return $result
        }

        if ($retryIteration -eq $MaxTries)
        {
            if ($exception)
            {
                throw $exception
            }
            else
            {
                throw (Get-VstsLocString -Key ActionTimedOut)
            }
        }

        Write-Host $RetryMessage
        $retryIteration++
        Start-Sleep $RetryIntervalInSeconds
    } while ($true)

    Trace-VstsLeavingInvocation $MyInvocation
}

function Get-TempDirectoryPath
{
    <#
    .SYNOPSIS
    Returns a temp directory path. Uses Agent.TempDirectory if available and shorter than env temp
    #>

    Param ()

    $agentTemp = Get-VstsTaskVariable -Name 'agent.tempDirectory'
    $envTemp = $env:Temp
    if ($agentTemp -and ($agentTemp.Length -le $envTemp.Length))
    {
        return $agentTemp
    }

    return $envTemp
}

function Test-RetryableException
{
    [CmdletBinding()]
    param(
        [System.Object]
        $Exception,

        [string[]]
        $RetryableExceptions
    )

    $RetryableExceptions | ForEach-Object {
        if ($_ -and ($Exception -is ([type]$_)))
        {
            return $true;
        }
    }

    return $false
}