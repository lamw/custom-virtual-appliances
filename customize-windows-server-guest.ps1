# William Lam
# www.virtuallyghetto.com
# Sample Network Customization script for Windows Server 2016 + Active Directory Domain join

$customizationRanFile = [System.Environment]::GetEnvironmentVariable('TEMP','Machine') + "\ran_customization"
$customizationLogFile = [System.Environment]::GetEnvironmentVariable('TEMP','Machine') + "\customization-log.txt"

if(! (Test-Path -LiteralPath $customizationRanFile)) {
    "Customization Started @ $(Get-Date)" | Out-File -FilePath $customizationLogFile

    $EthernetInterfaceAliasName = "Ethernet0"
    $VMwareToolsExe = "C:\Program Files\VMware\VMware Tools\vmtoolsd.exe"

    [xml]$ovfEnv = & $VMwareToolsExe --cmd "info-get guestinfo.ovfEnv" | Out-String
    $ovfProperties = $ovfEnv.ChildNodes.NextSibling.PropertySection.Property

    $ovfPropertyValues = @{}
    foreach ($ovfProperty in $ovfProperties) {
        $ovfPropertyValues[$ovfProperty.key] = $ovfProperty.Value
    }

    # uncomment below for debugging which will output all OVF Properties to logfile
    # $ovfProperties | Out-File -FilePath $customizationLogFile -Append

    # Configure Static IP
    if($ovfPropertyValues['guestinfo.hostname'] -ne "") {

        # Rename Computer & Description to match Hostname
        "Renaming Computer Name and Description to $($ovfPropertyValues['guestinfo.hostname'])" | Out-File -FilePath $customizationLogFile -Append
        Rename-Computer -NewName $ovfPropertyValues['guestinfo.hostname'] | Out-File -FilePath $customizationLogFile -Append
        Get-CimInstance -ClassName Win32_OperatingSystem | Set-CimInstance -Property @{Description = $ovfPropertyValues['guestinfo.hostname']} | Out-File -FilePath $customizationLogFile -Append

        # Configure Networking
        "Configuring IP Address to $($ovfPropertyValues['guestinfo.ipaddress'])" | Out-File -FilePath $customizationLogFile -Append
        "Configuring Netmask to $($ovfPropertyValues['guestinfo.netmask'])" | Out-File -FilePath $customizationLogFile -Append
        "Configuring Gateway to $($ovfPropertyValues['guestinfo.gateway'])" | Out-File -FilePath $customizationLogFile -Append
        New-NetIPAddress –InterfaceAlias $EthernetInterfaceAliasName -AddressFamily IPv4 –IPAddress $ovfPropertyValues['guestinfo.ipaddress'] –PrefixLength $ovfPropertyValues['guestinfo.netmask'] | Out-File -FilePath $customizationLogFile -Append
        New-NetRoute -DestinationPrefix 0.0.0.0/0 -InterfaceAlias $EthernetInterfaceAliasName -NextHop $ovfPropertyValues['guestinfo.gateway'] | Out-File -FilePath $customizationLogFile -Append

        # Configure DNS
        "Configuring DNS to $($ovfPropertyValues['guestinfo.dns'])" | Out-File -FilePath $customizationLogFile -Append
        Set-DnsClientServerAddress -InterfaceAlias $EthernetInterfaceAliasName -ServerAddresses $ovfPropertyValues['guestinfo.dns'] | Out-File -FilePath $customizationLogFile -Append
        # Sleep to ensure DNS changes go into effect for AD Join
        Start-Sleep -Seconds 5

        # Configure Active Directory
        if($ovfPropertyValues['guestinfo.ad_domain'] -ne "" -and $ovfPropertyValues['guestinfo.ad_username'] -ne "" -and $ovfPropertyValues['guestinfo.ad_password'] -ne "") {
            $joinCred = New-Object pscredential -ArgumentList ([pscustomobject]@{
                UserName = $ovfPropertyValues['guestinfo.ad_username'] + "@" + $ovfPropertyValues['guestinfo.ad_domain']
                Password = (ConvertTo-SecureString -String $ovfPropertyValues['guestinfo.ad_password'] -AsPlainText -Force)[0]
            })
            "Joining Active Directory Domain $($ovfPropertyValues['guestinfo.ad_domain'])" | Out-File -FilePath $customizationLogFile -Append
            Add-Computer -NewName $ovfPropertyValues['guestinfo.hostname'] -Domain $ovfPropertyValues['guestinfo.ad_domain'] -Credential $joinCred -Restart | Out-File -FilePath $customizationLogFile -Append
        }
    } else {
        "No OVF Properties were found, defaulting to DHCP for networking" | Out-File -FilePath $customizationLogFile -Append
    }

    # Create ran file to ensure we do not run again
	Out-File -FilePath $customizationRanFile
}