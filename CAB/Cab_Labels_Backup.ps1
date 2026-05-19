# ==============================================
#  Aktualizacia tlaciarni CAB - PowerShell
#  Created by: Lukas Zaslav
#  ⁄prava: pri voæbe 'all' kopÌruje vöetky s˙bory
#           z prieËinka \\sk-rds-01\CAB_DB\Labels
#           do vöetk˝ch tlaËiarnÌ (bez rozlÌöenia L/P)
# ==============================================

function Start-PrinterUpdate {
    Clear-Host
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host "  Aktualizacia tlaciarni CAB" -ForegroundColor Cyan
    Write-Host "  Labels update  - v20251030 " -ForegroundColor Red
    Write-Host "  Created by: Lukas Zaslav" -ForegroundColor Gray
    Write-Host "==============================`n"

    # ----------------------------------------------
    # Definicia IP adries tlaciarni
    # ----------------------------------------------
    $PrintersLeft = @{
        1 = "10.60.30.101"
        2 = "10.60.0.99"
        3 = "10.60.0.183"
        4 = "10.60.0.184"
        5 = "10.60.0.185"
    }

    $PrintersRight = @{
        6 = "10.60.0.186"
        7 = "10.60.0.187"
        8 = "10.60.0.188"
        9 = "10.60.0.189"
        10 = "10.60.0.190"
    }

    $AllPrinters = $PrintersLeft + $PrintersRight
    $PrinterStatus = @{}

    # ----------------------------------------------
    # Logovanie
    # ----------------------------------------------
    $LogDir = "\\sk-rds-01\Powershell\CAB\Log_labels"
    if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }

    $Timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $LogFile = Join-Path $LogDir "CAB_Update_$Timestamp.log"

    function Write-Log {
        param([string]$Message)
        Add-Content -Path $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
    }

    # ----------------------------------------------
    # Zobrazenie zoznamu tlaËiarnÌ
    # ----------------------------------------------
    Write-Host "Zoznam tlaËiarnÌ:" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------"
    Write-Host ("{0,-35} {1,-35}" -f "ºAV¡ STRANA", "PRAV¡ STRANA") -ForegroundColor Yellow
    Write-Host "------------------------------------------------------------"

    for ($i = 1; $i -le 5; $i++) {
        $leftIP = $PrintersLeft[$i]
        $rightIP = $PrintersRight[$i + 5]
        Write-Host ("{0,-35}{1,-35}" -f ("$i. $leftIP"), ("$($i+5). $rightIP")) -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Zadaj ËÌslo tlaËiarne (1-10) alebo napÌö 'all' pre aktualiz·ciu vöetk˝ch." -ForegroundColor Green
    $choice = Read-Host "Tvoja voæba"

    $script:ErrorsList = @()
    $script:SuccessCount = 0
    $script:TotalCount = 0
    $script:SkippedOffline = @()

    # ----------------------------------------------
    # Podprogram pre aktualiz·ciu tlaËiarne
    # ----------------------------------------------
    function Update-Printer {
        param([int]$Number, [string]$IPAddress)

        $script:TotalCount++
        $PrinterHasError = $false
        Write-Host "`nAktualizujem tlaËiareÚ Ë.$Number ($IPAddress)..." -ForegroundColor Yellow
        Write-Log "Spusten· aktualiz·cia tlaËiarne Ë.$Number - $IPAddress"

        try {
            # ?? Nov· jednotn· cesta pre vöetky tlaËiarne
            $localFolder = "\\sk-rds-01\CAB_DB\Labels"

            $ftpServer = "ftp://${IPAddress}/labels/"
            $user = "ftpcard"
            $password = "card"

            if (!(Test-Path $localFolder)) {
                $errMsg = "Lok·lny prieËinok '$localFolder' neexistuje!"
                Write-Host "$errMsg" -ForegroundColor Red
                Write-Log "ERROR - $errMsg"
                $script:ErrorsList += "[$Number | $IPAddress] $errMsg"
                return
            }

            $files = Get-ChildItem -Path $localFolder -File
            if ($files.Count -eq 0) {
                $errMsg = "V prieËinku '$localFolder' neboli n·jdenÈ ûiadne s˙bory!"
                Write-Host "$errMsg" -ForegroundColor Yellow
                Write-Log "WARNING - $errMsg"
                $script:ErrorsList += "[$Number | $IPAddress] $errMsg"
                return
            }

            foreach ($file in $files) {
                try {
                    $filePath = $file.FullName
                    $fileName = $file.Name
                    $uri = $ftpServer + $fileName

                    $ftpRequest = [System.Net.FtpWebRequest]::Create($uri)
                    $ftpRequest.Credentials = New-Object System.Net.NetworkCredential($user, $password)
                    $ftpRequest.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
                    $ftpRequest.UseBinary = $true
                    $ftpRequest.UsePassive = $true
                    $ftpRequest.KeepAlive = $false
                    $ftpRequest.Timeout = 8000

                    $fileContent = [System.IO.File]::ReadAllBytes($filePath)
                    $ftpRequest.ContentLength = $fileContent.Length

                    $requestStream = $ftpRequest.GetRequestStream()
                    $requestStream.Write($fileContent, 0, $fileContent.Length)
                    $requestStream.Close()

                    $response = $ftpRequest.GetResponse()
                    Write-Host "  S˙bor '$fileName' nahrat˝." -ForegroundColor Green
                    Write-Log "OK - S˙bor '$fileName' nahrat˝ na $IPAddress"
                    $response.Close()
                }
                catch {
                    $PrinterHasError = $true
                    $errMsg = "Chyba pri nahr·vanÌ '$($file.Name)': $($_.Exception.Message)"
                    Write-Host "  $errMsg" -ForegroundColor Red
                    Write-Log "ERROR - [$IPAddress] $errMsg"
                    $script:ErrorsList += "[$Number | $IPAddress] $errMsg"
                }
            }

            if (-not $PrinterHasError) {
                Write-Host "`nTlaËiareÚ Ë.$Number ($IPAddress) ˙speöne aktualizovan·.`n" -ForegroundColor Green
                Write-Log "TlaËiareÚ Ë.$Number ($IPAddress) ˙speöne aktualizovan·."
                $script:SuccessCount++
            } else {
                Write-Host "`nTlaËiareÚ Ë.$Number ($IPAddress) NEBOLA ˙speöne aktualizovan·.`n" -ForegroundColor Red
                Write-Log "TlaËiareÚ Ë.$Number ($IPAddress) NEBOLA ˙speöne aktualizovan·."
            }
        }
        catch {
            $errMsg = "Kritick· chyba pri aktualiz·cii Ë.$Number ($IPAddress): $($_.Exception.Message)"
            Write-Host "$errMsg" -ForegroundColor Red
            Write-Log "ERROR - $errMsg"
            $script:ErrorsList += "[$Number | $IPAddress] $errMsg"
        }
    }

    # ----------------------------------------------
    # Hlavn· logika
    # ----------------------------------------------
    if ($choice.ToLower() -eq "all") {
        Write-Host "`nPrebieha test dostupnosti tlaËiarnÌ... prosÌm Ëakajte.`n" -ForegroundColor Yellow
        Write-Host "------------------------------------------------------------"
        Write-Host ("{0,-35} {1,-35}" -f "ºAV¡ STRANA", "PRAV¡ STRANA") -ForegroundColor Yellow
        Write-Host "------------------------------------------------------------"

        for ($i = 1; $i -le 5; $i++) {
            $leftIP = $PrintersLeft[$i]
            $rightIP = $PrintersRight[$i + 5]

            $pingLeft = Test-Connection -ComputerName $leftIP -Count 2 -Quiet -ErrorAction SilentlyContinue
            $pingRight = Test-Connection -ComputerName $rightIP -Count 2 -Quiet -ErrorAction SilentlyContinue

            $PrinterStatus[$i] = if ($pingLeft) { "ONLINE" } else { "OFFLINE" }
            $PrinterStatus[$i + 5] = if ($pingRight) { "ONLINE" } else { "OFFLINE" }

            $leftColor = if ($pingLeft) { "Green" } else { "Magenta" }
            $rightColor = if ($pingRight) { "Green" } else { "Magenta" }

            Write-Host ("{0,-35}" -f ("$i. $leftIP [$($PrinterStatus[$i])]")) -ForegroundColor $leftColor -NoNewline
            Write-Host ("{0,-35}" -f ("$($i+5). $rightIP [$($PrinterStatus[$i+5])]")) -ForegroundColor $rightColor
        }

        Write-Host "`nTest dokonËen˝.`n" -ForegroundColor DarkGray

        foreach ($p in $AllPrinters.GetEnumerator() | Sort-Object Name) {
            if ($PrinterStatus[$p.Key] -eq "ONLINE") {
                Update-Printer -Number $p.Key -IPAddress $p.Value
            } else {
                $script:SkippedOffline += [PSCustomObject]@{ Number = $p.Key; IP = $p.Value }
            }
        }
    }
    elseif ($AllPrinters.ContainsKey([int]$choice)) {
        $ip = $AllPrinters[[int]$choice]
        Update-Printer -Number $choice -IPAddress $ip
    }
    else {
        Write-Host "`nNeplatn· voæba. Zadaj ËÌslo 1ñ10 alebo 'all'." -ForegroundColor Yellow
        return
    }

    # ----------------------------------------------
    # Zhrnutie
    # ----------------------------------------------
    Write-Host "`n===============================" -ForegroundColor Cyan
    Write-Host "   ZHRNUTIE AKTUALIZ¡CIE" -ForegroundColor Cyan
    Write-Host "===============================" -ForegroundColor Cyan
    Write-Host "Celkom spracovan˝ch: $($script:TotalCount)" -ForegroundColor White
    Write-Host "⁄speön˝ch: $($script:SuccessCount)" -ForegroundColor Green
    Write-Host "S chybami: $($script:TotalCount - $script:SuccessCount)" -ForegroundColor $(if (($script:TotalCount - $script:SuccessCount) -gt 0) { "Red" } else { "Green" })

    if ($script:SkippedOffline.Count -gt 0) {
        Write-Host "`nTlaËiarne, ktorÈ boli OFFLINE (kopÌrovanie neprebehlo):" -ForegroundColor Magenta
        foreach ($s in $script:SkippedOffline) {
            Write-Host ("  Ë.{0} - {1}" -f $s.Number, $s.IP) -ForegroundColor Magenta
        }
    }

    Write-Host "===============================" -ForegroundColor Cyan

    if ($script:ErrorsList.Count -gt 0) {
        Write-Host "`nZOZNAM CH›B:" -ForegroundColor Red
        foreach ($e in $script:ErrorsList) {
            Write-Host "  $e" -ForegroundColor Red
        }
    }

    Write-Host ""
    $again = Read-Host "Chceö aktualizovaù Ôalöiu tlaËiareÚ? (a/n)"
    if ($again -match "^(a|A|ano|y|yes)$") {
        Start-PrinterUpdate
    } else {
        Write-Host "`nProgram bol ukonËen˝. Log uloûen˝ do:`n$LogFile" -ForegroundColor Cyan
        Write-Log "Program ukonËen˝ pouûÌvateæom."
        exit
    }
}

# Spustenie programu
Start-PrinterUpdate
