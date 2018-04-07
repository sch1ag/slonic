# slonic
SLONIC is a SimpLe ONline Information Collector.  
It is a set of Perl scrips to collect operation system activity from CLI utilities, parse it and post to InfluxDB.  
Slonic use Core Perl and pure Perl modules only so it can potentially run on any UNIX like OS with Perl and without necessity to compile dependencies.  
Because of different output formats every utility on every OS requere its own "module" to parse and prepare data.  
At this time only Solaris 11 with limited numbers of utilities is supported:
* vmstat
* iostat
* dlstat
* vxstat

