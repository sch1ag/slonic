slonic
======
SLONIC is a SimpLe ONline Information Collector.  
It is a set of Perl scrips to collect operation system activity from CLI utilities, parse it and post to InfluxDB.  
Slonic use Core Perl and pure Perl modules only so it can potentially run on any UNIX like OS with Perl and without necessity to compile dependencies.  
Because of different output formats every utility on every OS requere its own "module" to parse and prepare data.  
  
At this time only Solaris 11 with limited numbers of utilities are supported:
* vmstat
* iostat
* dlstat
* vxstat
* sar (-mvc)

## Building ips package for Solaris 11  
> git clone https://github.com/sch1ag/slonic.git  
> cd slonic/  
> ./sunos11_mkproto.sh  
> ./sunos11_buildpkg.sh  

sunos11_buildpkg.sh must be executed on Solaris 11 (x86 or SPARC)  
After that you will get slonic.p5p that can be installed on Solaris 11 (it will run normally on booth x86 and SPARC) using pkg system  
  
> pkg install -g slonic.p5p slonic  

## Example of Grafana Panels

![slonic-dashboard-vmstat](https://i.ibb.co/fNVv86Q/slonic-dashboard-vmstat.png)
![slonic-dashboard-vxstat](https://i.ibb.co/1dQSRyg/slonic-dashboard-vxstat.png)
![slonic-dashboard-iostat](https://i.ibb.co/rd5Xm5N/slonic-dashboard-iostat.png)
![slonic-dashboard-dlstat](https://i.ibb.co/0MpFwK7/slonic-dashboard-dlstat.png)
![slonic-dashboard-vmstat-mem](https://i.ibb.co/BV8qqx9/slonic-dashboard-vmstat-mem.png)
![slonic-dashboard-sar](https://i.ibb.co/BZdgJND/slonic-dashboard-sar.png)
