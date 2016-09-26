## VMware Build - 3 Tier App ##
## Author: Anthony Burke t:@pandom_ b:networkinferno.net
## Revisions: Nick Bradford, Dimtri Desmidt
## version 1.4
## September 2016
#-------------------------------------------------- 
# ____   __   _  _  ____  ____  __ _  ____  _  _ 
# (  _ \ /  \ / )( \(  __)(  _ \(  ( \/ ___)( \/ )
#  ) __/(  O )\ /\ / ) _)  )   //    /\___ \ )  ( 
# (__)   \__/ (_/\_)(____)(__\_)\_)__)(____/(_/\_)
#     PowerShell extensions for NSX for vSphere
#--------------------------------------------------

<#
Copyright © 2015 VMware, Inc. All Rights Reserved.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 2, as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTIBILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License version 2 for more details.

You should have received a copy of the General Public License version 2 along with this program.
If not, see https://www.gnu.org/licenses/gpl-2.0.html.

The full text of the General Public License 2.0 is provided in the COPYING file.
Some files may be comprised of various open source software components, each of which
has its own license that is located in the source code of the respective component.”
#>

## Note: The OvfConfiguration portion of this example relies on this OVA. The securityGroup and Firewall configuration have a MANDATORY DEPENDANCY on this OVA being deployed at runtime. The script will fail if the conditions are not met. This OVA can be found here http://goo.gl/oBAFgq

# This paramter block defines global variables which a user can override with switches on execution.
param (
    #Names
    $TransitLsName = "Transit",
    $WebLsName = "Web",
    $AppLsName = "App",
    $DbLsName = "Db",
    $MgmtLsName = "Mgmt",
    $EdgeName = "Edge01",
    $LdrName = "Ldr01",

    #Infrastructure
    $EdgeUplinkPrimaryAddress = "192.168.100.192",
    $EdgeUplinkSecondaryAddress = "192.168.100.193",
    $EdgeInternalPrimaryAddress = "172.16.1.1",
    $EdgeInternalSecondaryAddress = "172.16.1.6",
    $LdrUplinkPrimaryAddress = "172.16.1.2",
    $LdrUplinkProtocolAddress = "172.16.1.3",
    $LdrWebPrimaryAddress = "10.0.1.1",
    $WebNetwork = "10.0.1.0/24",
    $LdrAppPrimaryAddress = "10.0.2.1",
    $AppNetwork = "10.0.2.0/24",
    $LdrDbPrimaryAddress = "10.0.3.1",
    $DbNetwork = "10.0.3.0/24",
    $TransitOspfAreaId = "10",

    #WebTier
    $Web01Name = "Web01",
    $Web01Ip = "10.0.1.11",
    $Web02Name = "Web02",
    $Web02Ip = "10.0.1.12",

    #AppTier
    $App01Name = "App01",
    $App01Ip = "10.0.2.11",
    $App02Name = "App02",
    $App02Ip = "10.0.2.12",
    $Db01Name = "Db01",
    $Db01Ip = "10.0.3.11",

    #DB Tier
    $Db02Name = "Db02",
    $Db02Ip = "10.0.3.12",

    #Subnet
    $DefaultSubnetMask = "255.255.255.0",
    $DefaultSubnetBits = "24",

    #Port
    $HttpPort = "80",

    #Management
    $ClusterName = "Management & Edge Cluster",
    $DatastoreName = "ds-site-a-nfs01",
    $Password = "VMware1!VMware1!",
    #Compute
    $ComputeClusterName = "Compute Cluster A",
    $EdgeUplinkNetworkName = "vds-mgt_Management Network",
    $computevdsname = "vds-site-a",
    #3Tier App
    $vAppName = "Books",
    $BooksvAppLocation = "C:\3_Tier-App-v1.6.ova",

    ##LoadBalancer
    $LbAlgo = "round-robin",
    $WebpoolName = "WebPool1",
    $ApppoolName = "AppPool1",
    $WebVipName = "WebVIP",
    $AppVipName = "AppVIP",
    $WebAppProfileName = "WebAppProfile",
    $AppAppProfileName = "AppAppProfile",
    $VipProtocol = "http",
    ##Edge NAT
    $SourceTestNetwork = "192.168.100.0/24",

    ## Securiry Groups
    $WebSgName = "SGTSWeb",
    $WebSgDescription = "Web Security Group",
    $AppSgName = "SGTSApp",
    $AppSgDescription = "App Security Group",
    $DbSgName = "SGTSDb",
    $DbSgDescription = "DB Security Group",
    $BooksSgName = "SGTSBooks",
    $BooksSgDescription = "Books ALL Security Group",
    #Security Tags
    $StWebName = "ST-3TA-Web",
    $StAppName = "ST-3TA-App",
    $StDbName = "ST-3TA-Db,",
    #DFW
    $FirewallSectionName = "Bookstore",

    $DefaultHttpMonitorName = "default_http_monitor",

    #Script control
    $BuildTopology=$true,
    $DeployvApp=$true,
    [Parameter (Mandatory=$false)]
    [ValidateSet("static","ospf")]
    $TopologyType="static"

)


###
# Do Not modify below this line! :)
###

Set-StrictMode -Version latest

## Validation of PowerCLI version. PowerCLI 6 is requried due to OvfConfiguration commands.

[int]$PowerCliMajorVersion = (Get-PowerCliVersion).major

if ( -not ($PowerCliMajorVersion -ge 6 ) ) { throw "OVF deployment tools requires PowerCLI version 6 or above" }

try {
    $Cluster = get-cluster $ClusterName -errorAction Stop
    $DataStore = get-datastore $DatastoreName -errorAction Stop
    $EdgeUplinkNetwork = get-vdportgroup $EdgeUplinkNetworkName -errorAction Stop
}
catch {
    throw "Failed getting vSphere Inventory Item: $_"
}

# Building out the required Logical Switches
function Build-LogicalSwitches {

    #Logical Switches
    write-host -foregroundcolor "Green" "Creating Logical Switches..."

## Creates four logical switches with each being assigned to a global varaible.
    $Global:TransitLs = Get-NsxTransportZone | New-NsxLogicalSwitch $TransitLsName
    $Global:WebLs = Get-NsxTransportZone | New-NsxLogicalSwitch $WebLsName
    $Global:AppLs = Get-NsxTransportZone | New-NsxLogicalSwitch $AppLsName
    $Global:DbLs = Get-NsxTransportZone | New-NsxLogicalSwitch $DbLsName
    $Global:MgmtLs = Get-NsxTransportZone | New-NsxLogicalSwitch $MgmtLsName


}

#Building out the DLR.
function Build-Dlr {

    ###
    # DLR

    # DLR Appliance has the uplink router interface created first.
    write-host -foregroundcolor "Green" "Creating DLR"
    $LdrvNic0 = New-NsxLogicalRouterInterfaceSpec -type Uplink -Name $TransitLsName -ConnectedTo $TransitLs -PrimaryAddress $LdrUplinkPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits
    # The DLR is created and assigned to a portgroup, and the datastore/cluster required
    $Ldr = New-NsxLogicalRouter -name $LdrName -ManagementPortGroup $MgmtLs -interface $LdrvNic0 -cluster $cluster -datastore $DataStore


    ## Adding DLR interfaces after the DLR has been deployed. This can be done any time if new interfaces are required.
    # Added to pipe to out-null to supporess output that we dont need.
    write-host -foregroundcolor Green "Adding Web LIF to DLR"
    $Ldr | New-NsxLogicalRouterInterface -Type Internal -name $WebLsName  -ConnectedTo $WebLs -PrimaryAddress $LdrWebPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null
    write-host -foregroundcolor Green "Adding App LIF to DLR"
    $Ldr | New-NsxLogicalRouterInterface -Type Internal -name $AppLsName  -ConnectedTo $AppLs -PrimaryAddress $LdrAppPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null
    write-host -foregroundcolor Green "Adding DB LIF to DLR"
    $Ldr | New-NsxLogicalRouterInterface -Type Internal -name $DbLsName  -ConnectedTo $DbLs -PrimaryAddress $LdrDbPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null


}

Function Configure-DlrDefaultRoute {

    ## DLR Routing - default route from DLR with a next-hop of the Edge.
    write-host -foregroundcolor Green "Setting default route on DLR to $EdgeInternalPrimaryAddress"
    ##The first line pulls the uplink name coz we cant assume we know the index ID
    $LdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $TransitLsName}
    Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -DefaultGatewayVnic $LdrTransitInt.index -DefaultGatewayAddress $EdgeInternalPrimaryAddress -confirm:$false | out-null

}

Function Build-Edge {

    # EDGE

    ## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addreses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
    $edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $EdgeUplinkPrimaryAddress -SecondaryAddress $EdgeUplinkSecondaryAddress -SubnetPrefixLength $DefaultSubnetBits
    $edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $EdgeInternalPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits -SecondaryAddress $EdgeInternalSecondaryAddress

    ## Deploy appliance with the defined uplinks
    write-host -foregroundcolor "Green" "Creating Edge"
    $Global:Edge1 = New-NsxEdge -name $EdgeName -cluster $Cluster -datastore $DataStore -Interface $edgevnic0,$edgevnic1 -Password $Password


}

function Set-EdgeFwDefaultAccept {

     #Change the default FW policy of the edge.  At the time of writing there is not  an explicit cmdlet to do this, so we update the XML manually and push it back using Set-NsxEdge
    write-host -foregroundcolor "Green" "Setting $EdgeName firewall default rule to permit"
    $Edge1 = get-nsxedge $Edge1.name
    $Edge1.features.firewall.defaultPolicy.action = "accept"
    $Edge1 | Set-NsxEdge -confirm:$false | out-null

}

function Set-Edge-Db-Nat {
    write-host -foregroundcolor "Green" "Using the devils technology - NAT - to expose access to the Database VM"
    $SrcNatPort = 3306
    $TranNatPort = 3306
    Get-NsxEdge $EdgeName | Get-NsxEdgeNat | Set-NsxEdgeNat -enabled -confirm:$false | out-null
    $DbNat = get-NsxEdge $EdgeName | Get-NsxEdgeNat | New-NsxEdgeNatRule -vNic 0 -OriginalAddress $SourceTestNetwork -TranslatedAddress $Db01Ip -action dnat -Protocol tcp -OriginalPort $SrcNatPort -TranslatedPort $TranNatPort -LoggingEnabled -Enabled -Description "Open SSH on port $SrcNatPort to $TranNatPort"

}

function Set-EdgeStaticRoute {

    write-host -foregroundcolor "Green" "Adding static route to Web, App and DB networks to $EdgeName"
    ##Static route from Edge to Web and App via DLR Uplink if -topologytype is not defined or static selected
    Get-NsxEdge $EdgeName | Get-NsxEdgerouting | New-NsxEdgestaticroute -Network $WebNetwork -NextHop $LdrUplinkPrimaryAddress -confirm:$false | out-null
    Get-NsxEdge $EdgeName | Get-NsxEdgerouting | New-NsxEdgestaticroute -Network $AppNetwork -NextHop $LdrUplinkPrimaryAddress -confirm:$false | out-null
    Get-NsxEdge $EdgeName | Get-NsxEdgerouting | New-NsxEdgestaticroute -Network $DbNetwork -NextHop $LdrUplinkPrimaryAddress -confirm:$false | out-null

}

function Configure-EdgeOSPF {
    #If -TopoologyType ospf is selected then this function is run.
    write-host -foregroundcolor Green "Configuring Edge OSPF"
    Get-NsxEdge $EdgeName | Get-NsxEdgerouting | set-NsxEdgeRouting -EnableOspf -RouterId $EdgeUplinkPrimaryAddress -confirm:$false | out-null

    #Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
    Get-NsxEdge $EdgeName | Get-NsxEdgerouting | Get-NsxEdgeOspfArea -AreaId 51 | Remove-NsxEdgeOspfArea -confirm:$false

    #Create new Area 0 for OSPF
    Get-NsxEdge $EdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfArea -AreaId $TransitOspfAreaId -Type normal -confirm:$false | out-null

    #Area to interface mapping
    Get-NsxEdge $EdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId $TransitOspfAreaId -vNic 1 -confirm:$false | out-null

}

function Configure-LogicalRouterOspf {

    write-host -foregroundcolor Green "Configuring Logicalrouter OSPF"
    Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableOspf -EnableOspfRouteRedistribution -RouterId $LdrUplinkPrimaryAddress -ProtocolAddress $LdrUplinkProtocolAddress -ForwardingAddress $LdrUplinkPrimaryAddress  -confirm:$false | out-null

    #Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
    Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId 51 | Remove-NsxLogicalRouterOspfArea -confirm:$false

    #Create new Area
    Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId $TransitOspfAreaId -Type normal -confirm:$false | out-null

    #Area to interface mapping
    $LdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $TransitLsName}

    Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfInterface -AreaId $TransitOspfAreaId -vNic $LdrTransitInt.index -confirm:$false | out-null

    #Enable Redistribution into OSPF of connected routes.
    Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -Learner ospf -FromConnected -Action permit -confirm:$false | out-null

}

function Build-LoadBalancer {

    # Switch that enables Loadbanacing on $EdgeName
    write-host -foregroundcolor "Green" "Enabling LoadBalancing on $EdgeName"
    Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | Set-NsxLoadBalancer -Enabled | out-null

    # Edge LB config - define pool members.  By way of example, we will use two different methods for defining pool membership.  Webpool via predefine memberspec first...
    write-host -foregroundcolor "Green" "Creating Web Pool"

    $webpoolmember1 = New-NsxLoadBalancerMemberSpec -name $Web01Name -IpAddress $Web01Ip -Port $HttpPort
    $webpoolmember2 = New-NsxLoadBalancerMemberSpec -name $Web02Name -IpAddress $Web02Ip -Port $HttpPort

    # ... And create the web pool
    $WebPool =  Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name $WebPoolName -Description "Web Tier Pool" -Transparent:$false -Algorithm $LbAlgo -Memberspec $webpoolmember1,$webpoolmember2

    # Now, method two for the App Pool  Create the pool with empty membership.
    write-host -foregroundcolor "Green" "Creating App Pool"
    $AppPool = Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name $AppPoolName -Description "App Tier Pool" -Transparent:$false -Algorithm $LbAlgo

    # ... And now add the pool members
    $AppPool = $AppPool | Add-NsxLoadBalancerPoolMember -name $App01Name -IpAddress $App01Ip -Port $HttpPort
    $AppPool = $AppPool | Add-NsxLoadBalancerPoolMember -name $App02Name -IpAddress $App02Ip -Port $HttpPort

    # Create App Profiles. It is possible to use the same but for ease of operations this will be two.
    write-host -foregroundcolor "Green" "Creating Application Profiles for Web and App"
    $WebAppProfile = Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerApplicationProfile -Name $WebAppProfileName  -Type $VipProtocol
    $AppAppProfile = Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | new-NsxLoadBalancerApplicationProfile -Name $AppAppProfileName  -Type $VipProtocol

    # Create the VIPs for the relevent WebPools. Applied to the Secondary interface variables declared.
    write-host -foregroundcolor "Green" "Creating VIPs"
    Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | Add-NsxLoadBalancerVip -name $WebVipName -Description $WebVipName -ipaddress $EdgeUplinkSecondaryAddress -Protocol $VipProtocol -Port $HttpPort -ApplicationProfile $WebAppProfile -DefaultPool $WebPool -AccelerationEnabled | out-null
    Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | Add-NsxLoadBalancerVip -name $AppVipName -Description $AppVipName -ipaddress $EdgeInternalSecondaryAddress -Protocol $VipProtocol -Port $HttpPort -ApplicationProfile $AppAppProfile -DefaultPool $AppPool -AccelerationEnabled | out-null

}
## NOTE: From here below this requires the OVF that VMware uses internally. Please customise for your three tier application. This works for OVA1.6
function deploy-3TiervApp {
  write-host -foregroundcolor "Green" "Deploying 'The Bookstore' application "
  # vCenter and the VDS has no understanding of a "Logical Switch". It only sees it as a VDS portgroup. This looks up the Logical Switch defined by the variable $WebLsName and runs iterates the result across Get-NsxBackingPortGroup. The results are used below in the networkdetails section.
  $WebNetwork = get-nsxtransportzone | get-nsxlogicalswitch $WebLsName | Get-NsxBackingPortGroup
  $AppNetwork = get-nsxtransportzone | get-nsxlogicalswitch $AppLsName | Get-NsxBackingPortGroup
  $DbNetwork = get-nsxtransportzone | get-nsxlogicalswitch $DbLsName | Get-NsxBackingPortGroup

  $WebNetwork = $webnetwork | ? {$_.vdswitch.name -eq ("$computevdsname")}
  $AppNetwork = $AppNetwork | ? {$_.vdswitch.name -eq ("$computevdsname")}
  $DbNetwork = $DbNetwork | ? {$_.vdswitch.name -eq ("$computevdsname")}

  $WebNetwork = $WebNetwork.name
  $AppNetwork = $AppNetwork.name
  $DbNetwork = $DbNetwork.name

  $ComputeCluster = Get-Cluster $ComputeClusterName
  
  ## Compute details - finds the host with the least used memory for deployment.
  $VMHost =  $ComputeCluster | Get-VMHost | Sort MemoryUsageGB | Select -first 1
  ## Using the PowerCLI command, get OVF draws on the location of the OVA from the defined variable.
  $OvfConfiguration = Get-OvfConfiguration -Ovf $BooksvAppLocation


  #networkdetails need to be defined.
  $OvfConfiguration.NetworkMapping.vxw_dvs_24_virtualwire_3_sid_10001_Web_LS_01.Value = "$WebNetwork"
  $OvfConfiguration.NetworkMapping.vxw_dvs_24_virtualwire_4_sid_10002_App_LS_01.Value = "$AppNetwork"
  $OvfConfiguration.NetworkMapping.vxw_dvs_24_virtualwire_5_sid_10003_DB_LS_01.Value = "$DbNetwork"

  ## VMdetails
  $OvfConfiguration.common.app_ip.Value = $EdgeInternalSecondaryAddress
  $OvfConfiguration.common.Web01_IP.Value = $Web01Ip
  $OvfConfiguration.common.Web02_IP.Value = $Web02Ip
  $OvfConfiguration.common.Web_Subnet.Value = $DefaultSubnetMask
  $OvfConfiguration.common.Web_Gateway.Value = $LdrWebPrimaryAddress
  $OvfConfiguration.common.App01_IP.Value = $App01Ip
  $OvfConfiguration.common.App02_IP.Value = $App02Ip
  $OvfConfiguration.common.App_Subnet.Value = $DefaultSubnetMask
  $OvfConfiguration.common.App_Gateway.Value = $LdrAppPrimaryAddress
  $OvfConfiguration.common.DB01_IP.Value = $DB01Ip
  $OvfConfiguration.common.DB_Subnet.Value = $DefaultSubnetMask
  $OvfConfiguration.common.DB_Gateway.Value = $LdrDbPrimaryAddress

#With all the desired OVF configuration done it is time to run the deployment.
  Import-vApp -Source $BooksvAppLocation -OvfConfiguration $OvfConfiguration -Name $vAppName -Location $ComputeCluster -VMHost $Vmhost -Datastore $Datastore | out-null
  write-host -foregroundcolor "Green" "Starting $vAppName vApp components"
  Start-vApp $vAppName | out-null
}

function Apply-Microsegmentation {

    write-host -foregroundcolor Green "Getting Services"
    #This assumes they exist, which they do in the default NSX deployment.
    $httpservice = Get-NsxService HTTP
    $mysqlservice = Get-NsxService MySQL

    write-host -foregroundcolor "Green" "Creating Source IP Groups"
    #
    $AppVIP_IpSet = New-NsxIPSet -Name AppVIP_IpSet -IPAddresses $EdgeInternalSecondaryAddress
    $InternalESG_IpSet = New-NsxIPSet -name InternalESG_IpSet -IPAddresses $EdgeInternalPrimaryAddress
    $SourceNATnetwork = new-NsxIpSet -name "Source_Network" -IpAddresses $SourceTestNetwork

    write-host -foregroundcolor "Green" "Creating Security Tags and appending them"
    $STWeb = New-NsxSecurityTag $StWebName 
    $STApp = New-NsxSecurityTag $STAppName
    $STDb = New-NsxSecurityTag $STDbName

    $WebVM = get-vm | ? {$_.name -match ("Web0")}
    $AppVM = get-vm | ? {$_.name -match ("App0")}
    $DbVM = get-vm | ? {$_.name -match ("Db0")}

    $WebVM | New-NsxSecurityTagAssignment -ApplyTag $StWeb
    $AppVM | New-NsxSecurityTagAssignment -ApplyTag $StApp
    $DbVM | New-NsxSecurityTagAssignment -ApplyTag $StDb

    write-host -foregroundcolor "Green" "Creating Security Groups"
    #Creates the Web SecurityGroup and creates a static includes based on VMname Web0 which will match Web01 and Web02
    $WebSg = New-NsxSecurityGroup -name $WebSgName -description $WebSgDescription -includemember $STWeb
     #Creates the App SecurityGroup and creates a static includes based on VMname App0 which will match App01 and App02
    $AppSg = New-NsxSecurityGroup -name $AppSgName -description $AppSgDescription -includemember $STApp
     #Creates the Db SecurityGroup and creates a static includes based on VMname Db0 which will match Db01
    $DbSg = New-NsxSecurityGroup -name $DbSgName -description $DbSgDescription -includemember  $StDb
     #Creates the Books SecurityGroup and creates a static includes Security Group Web/App/Db and in turn its members
    $BooksSg = New-NsxSecurityGroup -name $BooksSgName -description $BooksSgName  -includemember $WebSg,$AppSg,$DbSg

    #Building firewall section with value defined in $FirewallSectionName
    write-host -foregroundcolor "Green" "Creating Firewall Section"

    $FirewallSection = new-NsxFirewallSection $FirewallSectionName

    #Actions
    $AllowTraffic = "allow"
    $DenyTraffic = "deny"
    #Allows Test network via NAT to reach DB VM
    $NatRule = get-NsxFirewallSection $FirewallSectionName | New-NsxFirewallRule -Name "$SourceTestNetwork to $DbSgName" -Source $SourceNatNetwork -Destination $DbSg -service $MySqlService -Action $Allowtraffic -AppliedTo $DbSg -position bottom

    #Allows Web VIP to reach WebTier
    write-host -foregroundcolor "Green" "Creating Web Tier rule"
    $SourcesRule = get-nsxfirewallsection $FirewallSectionName | New-NSXFirewallRule -Name "VIP to Web" -Source $InternalESG_IpSet -Destination $WebSg -Service $HttpService -Action $AllowTraffic -AppliedTo $WebSg -position bottom
    #Allows Web tier to reach App Tier via the APP VIP and then the NAT'd vNIC address of the Edge
    write-host -foregroundcolor "Green" "Creating Web to App Tier rules"
    $WebToAppVIP = get-nsxfirewallsection $FirewallSectionName | New-NsxFirewallRule -Name "$WebSgName to App VIP" -Source $WebSg -Destination $AppVIP_IpSet -Service $HttpService -Action $AllowTraffic -AppliedTo $WebSg,$AppSg -position bottom
    $ESGToApp = get-NsxFirewallSection $FirewallSectionName | New-NsxFirewallRule -Name "App ESG interface to $AppSgName" -Source $InternalEsg_IpSet -Destination $appSg -service $HttpService -Action $Allowtraffic -AppliedTo $AppSg -position bottom
    #Allows App tier to reach DB Tier directly
    write-host -foregroundcolor "Green" "Creating Db Tier rules"
    $AppToDb = get-nsxfirewallsection $FirewallSectionName | New-NsxFirewallRule -Name "$AppSgName to $DbSgName" -Source $AppSg -Destination $DbSg -Service $MySqlService -Action $AllowTraffic -AppliedTo $AppSg,$DbSG -position bottom
    write-host -foregroundcolor "Green" "Creating deny all applied to $BooksSgName"
    #Default rule that wraps around all VMs within the topolgoy - application specific DENY ALL
    $BooksDenyAll = get-nsxfirewallsection $FirewallSectionName | New-NsxFirewallRule -Name "Deny All Books" -Action $DenyTraffic -AppliedTo $BooksSg -position bottom -EnableLogging -tag "$BooksSG"
    write-host -foregroundcolor "Green" "Segmentation Complete - Application Secure"
}
if ( $BuildTopology ) {

    Build-LogicalSwitches
    Build-Dlr
    Configure-DlrDefaultRoute
    Build-Edge
    Set-EdgeFwDefaultAccept
    Set-Edge-Db-Nat
    Build-LoadBalancer
    switch ( $TopologyType ) {
        "static"  {
            Set-EdgeStaticRoute
        }

        "ospf" {
            Configure-EdgeOSPF
            Configure-LogicalRouterOSPF
        }
    }


 }
if ( $DeployvApp ) {
  deploy-3TiervApp
  Apply-Microsegmentation
}
