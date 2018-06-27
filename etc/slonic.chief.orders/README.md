#slonic.chief.orders files 
Every json file in the directories ${SLONIC_HOME}/etc/slonic.chief.orders (1) and ${SLONIC_ETC}/etc/slonic.chief.orders (2) is a start configuration for a module.
If there is a files with the same name in (1) and (2) this files will be merged with priority of (2). 

##FORCE_SWITCH
* on/true/yes/enable/enabled/1 - ignore CONDITION and run module (case is ignored)  
* off/false/no/disable/disabled/0 - ignore CONDITION and do not run module (case is ignored)  
* any other value - ignore FORCE_SWITCH and evaluate CONDITION  

