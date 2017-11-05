
[cmdletbinding()]

param (
   
    $vm,
    $cluster,
    $prefixgraphite = "vCenter",
    $startoffset = 60,
    $stopoffset = 0,
    $vcenter,
    $graphiteserver
)

Add-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue

if($global:DefaultVIServers.Count -eq 0){

    connect-viserver -server $vcenter -Protocol https 
}

if(-not $cluster) {
    write-verbose "Please specifcy the cluster name with the -cluster option"
    exit 1
}


function get-virtual-machines { 

    param($cluster,$vms)

    if(-not $vms) {
        write-verbose "Creating list of virtual machines..."
        $vm = get-cluster $cluster | Get-VM | where {$_.PowerState -eq "PoweredOn"}

    }else {
        write-verbose "Collecting info for specified VMs..."
        $vm = get-cluster $cluster | Get-VM -name $vms 
    }
    return $vm
}



function get-raw-stats {

    param(  $vm,
            $metrics,
            $startdate,
            $stopdate)

    
    if($commandlinestats){
        write-verbose "Stats from command line variable..."
        $rawstats = $stats 
    }else{
        $minutes = $stopdate-$startdate
        write-verbose "Collecting statistics for the last $minutes"
        $rawstats = Get-Stat -Realtime -Stat $metrics -Entity $vm -Start $startdate -finish $stopdate
    }
    return $rawstats
}


function process-raw-stats {

    param($stats)

    $carbonserver = $graphiteserver
    $carbonserverport = 2003
    $socket = New-Object System.Net.Sockets.TCPClient
    $socket.connect($CarbonServer, $CarbonServerPort)
    $stream = $socket.GetStream()
    $writer = new-object System.IO.StreamWriter($stream)


    $size = $stats.count
    write-verbose "Writing $size records to Graphite"

    $regex = "scsi|naa" 

    foreach($record in $stats){
    
                $metricpath = "Error"
                $vmname = $record.Entity
                $m = $record.metricid -replace "\.","_" #sanitise metricname to get flat metrics in graphite
                
                $instance = $record.Instance
               
                if($instance){
                         
                        if( $instance -match $regex){
                            
                            $metricpath = "$prefixgraphite.$cluster.VMs.$vmname.$instance.$m"

                        }else{

                            continue
                        }

                }else{
                    
                    $metricpath = "$prefixgraphite.$cluster.VMs.$vmname.$m"
                  
                }

                $value = $record.Value
                
                # Ajusted for NL TIME!!!!!!!!
                $UnixTime = [long][Math]::Floor((($record.timestamp - (New-Object DateTime 1970, 1, 1, 1, 0, 0, ([DateTimeKind]::Utc))).Ticks / [timespan]::TicksPerSecond))
                $metricstring = "$metricpath $value $UnixTime"
                #write-output "$metricstring"
                $writer.WriteLine($metricString)
                #$writer.Flush()

    }

    $writer.close()
    $socket.Close()

}

function process-vm { 
        
    param ([String]$virtualmachine)

    $metrics =  "disk.numberread.summation",
                "disk.numberwrite.summation",
                "disk.usage.average",
                "disk.maxTotalLatency.latest",
                "net.bytesRx.average",
                "net.bytesTx.average",
                "cpu.usage.average",
                "cpu.usagemhz.average",
                "cpu.system.summation",
                "cpu.wait.summation",
                "cpu.ready.summation",
                "cpu.idle.summation",
                "cpu.used.summation",
                "virtualDisk.read.average",
                "virtualDisk.write.average",
                "virtualDisk.totalReadLatency.average",
                "virtualDisk.totalWriteLatency.average",
                "cpu.latency.average",
                "cpu.costop.summation",
                "mem.latency.average"
             
   
    $startdate = (Get-Date).AddMinutes(-$startoffset)
    $stopdate = (Get-Date).AddMinutes(-$stopoffset)
    
    $sta = (get-date)
    $stats = get-raw-stats $virtualmachine $metrics $startdate $stopdate
    $sto = (get-date)
    $d =  ($sto - $sta)
    Write-verbose "Retrieving statistics data from vCenter took: $d" 
    
    Write-verbose "/\/\/-> Dumping metric data to Graphite"
    $sta = (get-date)
    
    process-raw-stats $stats
   
    $sto = (get-date)
    $d =  ($sto - $sta)
    Write-verbose "Dumping stats to Graphite took: $d" 
    
}


Function main {

   $start = (get-date)
      
   $vms = get-virtual-machines $cluster 

   $count = $vms.count
   $counter = 1
   

    foreach ($v in ($vms.name)) {

        write-progress -Activity "Processing metric data..." -status "Processing VM $counter of $count" -PercentComplete ($counter / $count*100)
        write-verbose "------------------------------"
        write-verbose "Processing virtual machine $v"
        $counter++
            

        $sta = (get-date)
        process-vm $v
        $sto = (get-date)
        $d =  ($sto - $sta)
        Write-verbose "Processing virtual machine took: $d"   
      
    }
  
    $stop = (get-date)
    $duration = ($stop-$start)

    Write-verbose "Duration is $duration"

}

main







