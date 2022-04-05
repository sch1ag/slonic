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

![slonic_dashboard_vmstat](https://user-images.githubusercontent.com/4456811/161803556-0696b354-d761-4f91-84f9-d952294c8667.png)
![slonic_dashboard_vmstat_mem](https://user-images.githubusercontent.com/4456811/161803538-d3e8aaf2-0ab5-4928-a05a-ecf3ec489354.png)
![slonic_dashboard_iostat](https://user-images.githubusercontent.com/4456811/161803552-f083e647-6178-4c27-9c00-90f1328ea482.png)
![slonic_dashboard_vxstat](https://user-images.githubusercontent.com/4456811/161803558-38b95cb2-9f52-4b0c-b2c1-738df4e616ea.png)
![slonic_dashboard_sar](https://user-images.githubusercontent.com/4456811/161803544-243a6c8b-4734-4d89-8dab-7b64806cf38f.png)
![slonic_dashboard_dlstat](https://user-images.githubusercontent.com/4456811/161803548-d00f2c05-3f2c-482f-a963-b3aaa46c02b3.png)
