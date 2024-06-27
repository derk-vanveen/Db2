#!/bin/ksh
#set -xv
#
# Script: audit_instance_111.sh
# Auteur: Karin Leisink / revisie 10.5 Bert Grootjans / Uitgebreidere opzet Derk van Veen
#         Kopie op de pvm00101 van de uitgebreide 10.5 versie van Derk van de pvm00051. Wel al op basis van 11.1 audit tabellen 
#         Te testen op de pvm00101 in dezelfde /opt/db2audit directory als de 10.5 versie, op database IG0ADPDB met alvast hoger versienummer _111.
#         In het 10_5 script is db2ipr09 uitgezonderd, want die moet juist met dit script verwerkt worden, terwijl in dit script alles behalve db2ipr09 
#         wordt uitgezonderd. Dit gebeurt hier vlak onder, met een extra exit  tussen de test op een actieve instance, en de test op een herstart.  

# Datum : 2020-01-27
# Versie: 2.0.1

# TO DO: auditlobs file ook naar delhist directory brengen!!!!
#
# Algemeen: voor de verwerking van 10.5 databases zijn nieuwe versies van de DS1 tabellen, en de RUBRIEKEN tabel nodig
#           Hiervoor wordt een suffix toegepast. Van de runbrieken tabel is er maar 1, en die kan als variabele gebruikt worden
#            maar de DS1 tabellen worden op een paar plekken in de code bepaald, en aldaar van het suffix vorozien. 
# 
# Aanroep per instance vanuit bulkinst06.sh, en dus is er binnen dit script altijd maar 1 DB2 versie.

case ${DB2MAINLEVEL} in
     "9"  ) VERSIE_SUFFIX=''
            ;;
     "10" ) VERSIE_SUFFIX='_111'
              ;;
     "11" ) VERSIE_SUFFIX='_111'
              ;;
        * ) VERSIE_SUFFIX='_111'
              ;;
esac

### check of de opgegeven instancenaam correct is
INSTANCE_PROC=`ps -ef | grep db2sysc|grep -v grep | grep -i $DB2INSTANCE |awk '{print  $1 }  '`
if [[ $INSTANCE_PROC = ""  ]]; then
   print "Ongeldige instancenaam  of inactieve instance opgegeven als argument"
   exit 9
fi


#######################################################################################################
#
### begin functies
# 
function doe_cmdb_connect
{
 	RT=0
 	db2 $CMDB_CONNECT_STAT
	RT=$(($RT+$?))
	if  [ "$RT" -gt 0 ] ; then db2 connect reset ;  exit $RT ; fi
	return
}
#
function set_query_optimization
{
        RT=0
        OPT_STATEMENT="set current query optimization 0"
        db2 $OPT_STATEMENT
        RT=$(($RT+$?))
        if  [ "$RT" -gt 0 ] ; then echo 'set current query optimization 0 statement niet gelukt' ;  fi
        return
}
# logmessage: arg1 = logmessage, arg2 = aantal records, arg3 = fatalerror, arg2 en arg3 zijn optioneel
function logmessage
{
        RT=0
	FATAL=0
 	if [[ $# -eq 0 ]];then
   	   print "Geen logmessage als argument opgegeven"
	   return
	fi
	MESSAGE=$1
	QUERY=''
	if [[ $# -gt 1 ]];then
	   NR_OF_RECS=$2
	   QUERY="insert into AUDIT.AUDIT_LOG (AUDIT_RUNTIME, SERVER, INSTANCE, NR_OF_RECORDS, MESSAGE, LOG_TIMESTAMP) values('$AUDITRUN_TS','$HOST','$DB2INSTANCE', $NR_OF_RECS, '$MESSAGE', CURRENT TIMESTAMP)"
	   if [[ $# -gt 2 ]];then
	      FATAL=$3
	      QUERY="insert into AUDIT.AUDIT_LOG (AUDIT_RUNTIME, SERVER, INSTANCE, NR_OF_RECORDS, MESSAGE, FATAL_ERROR, LOG_TIMESTAMP) values('$AUDITRUN_TS','$HOST','$DB2INSTANCE', $NR_OF_RECS, '$MESSAGE', $FATAL, CURRENT TIMESTAMP)"	
	   fi
	else
	   QUERY="insert into AUDIT.AUDIT_LOG (AUDIT_RUNTIME, SERVER, INSTANCE, NR_OF_RECORDS, MESSAGE, LOG_TIMESTAMP) values('$AUDITRUN_TS','$HOST','$DB2INSTANCE', NULL, '$MESSAGE', CURRENT TIMESTAMP)"
	fi

	db2 $QUERY
	RT=$(($RT+$?))
	if  [ "$RT" -gt 0 ] ; then db2 rollback; sluitaf $RT ; exit $RT ; fi
	db2 commit;
	RT=$(($RT+$?))
	if  [ "$RT" -gt 0 ] ; then db2 rollback; sluitaf $RT ; exit $RT ; fi
	if [ "$FATAL" -ge 1 ] ; then echo "exit, want FATAL ERROR!!!!!!!!!!!"; sluitaf $FATAL  ; exit $FATAL ; fi
	return	
}

function claim_audit_resources
{	
	RT=0 
 	#check of de admindb audit resources available zijn
	set -A resultset $(db2 -x "select available, lasthost, lastinstance, max(ts_status_update) as ts_status_update from AUDIT.AUDIT_ADMINDB_STATUS group by available, lasthost, lastinstance ")
	RT=$(($RT+$?))
	TEXT="Auditresource niet benaderbaar. Returncode: "$RT
	if  [[ $RT -gt 0 ]] ; then logmessage "$TEXT" null 1 ; sluitaf $RT ; exit $RT ; fi

	beschikbaar=${resultset[0]}
	server=${resultset[1]}
	instantie=${resultset[2]}
	tijdstip=${resultset[3]}

        if [ "$beschikbaar" -ne 1 ]  
	then 
	    RT=9
	    TEXT="Auditresource niet beschikbaar, status "$beschikbaar" , bezet door server "$server" en instantie "$instantie" op tijdstip "$tijdstip 
   	    print $TEXT
	    logmessage "$TEXT" null 1 
   	    sluitaf $RT
   	    exit $RT
	else 
	    QUERY="update AUDIT.AUDIT_ADMINDB_STATUS set available = 0, lasthost = '$HOST', lastinstance = '$DB2INSTANCE', TS_STATUS_UPDATE = '$AUDITRUN_TS' where available = 1 "
   	    db2 $QUERY
   	    RT=$(($RT+$?)) 
	    TEXT="Claimen van beschikbare auditresource middels update in status tabel is mislukt. Returncode: "$RT
	    if  [ "$RT" -gt 0 ] ; then db2 rollback ; logmessage "$TEXT" null 1 ; sluitaf $RT ; exit $RT ; fi
   	    db2 commit
   	    RT=$(($RT+$?))
	    TEXT="Claimen van beschikbare auditresource middels commit van update in status tabel is mislukt. Returncode: "$RT
	    if  [ "$RT" -gt 0 ] ; then db2 rollback ; logmessage "$TEXT" null 1 ; sluitaf $RT ; exit $RT ; fi
	fi
	return
}
function release_audit_resources
{
 	# !! hier niet de sluitaf functie aanroepen, want dan krijg je een oneindige loop !!!
	db2 "update AUDIT.AUDIT_ADMINDB_STATUS set available = 1, TS_STATUS_UPDATE = current timestamp where available = 0 and lasthost = '$HOST' and lastinstance = '$DB2INSTANCE' "
	TEKST="beschikbaar maken van audit admin resources middels update in status tabel is mislukt. Returncode: "$?
	if [ $? -gt 0 ] ; then db2 rollback ; logmessage "$TEKST" null 1 ;  exit $RT ; fi
	db2 commit
	TEKST="beschikbaar maken van audit admin resources middels commit van update in status tabel is mislukt. Returncode: "$?
	if [ $? -gt 0 ] ; then db2 rollback ; logmessage "$TEKST" null 1 ;  exit $RT ; fi
	return
}
function sluitaf
{
 	MAX_RT=0
	if [[ $# -ge 2 ]];then
	   MAX_RT=$2
	fi
	echo 'MAX_RT: '$MAX_RT

 	if [[ $# -gt 0 && $1 -gt $MAX_RT ]];then
   	   TEKST=$MODE_TEKST" gestopt vanwege fouten"
	else
   	   TEKST=$MODE_TEKST" succesvol"	
	fi

        logmessage "$TEKST"	
	release_audit_resources
	db2 connect reset
	return 
}
function update_phase
{
	RT=0
        echo 'in update_phase'
        if [[ $# -ne 1 ]]; then
            echo "Illegal number of parameters"
            exit 2
        fi

        completed_phase=$1

        case ${completed_phase} in
            "process_audit_data" | "load_extracted_data" | "filter_staging_tabel" | "stage_audit_data" | "ready" )
                db2 "update AUDIT.DATABASE_STATUS set phase = '${completed_phase}', AUDITRUN_TS = '${AUDITRUN_TS}' where host = '$HOST' and instance = '$DB2INSTANCE' "
                RT=$(($RT+$?))

	        if [  "$RT" -eq 1 ]
	        then
	            echo "De host, instance combinatie wordt nu toegevoegd aan de tabel  AUDIT.DATABASE_STATUS"
	            db2 "insert into AUDIT.DATABASE_STATUS (host, instance, phase, AUDITRUN_TS) values ('$HOST', '$DB2INSTANCE', '${completed_phase}', '${AUDITRUN_TS}')"
	            # We tellen de return codes bij elkaar op, zodat het totaal groter is dan 1 als ook de insert niet lukt. Het totaal wordt dan groter dan 1, waardoor de foutafhandeling klopt. 
	            RT=$(($RT+$?))
	        fi 

                if  [ "$RT" -gt 1 ] ; then db2 rollback;  sluitaf $RT 1 ; exit $RT; fi

	        db2 commit;
                RT=$(($RT+$?))
                if  [ "$RT" -gt 1 ] ; then db2 rollback;  sluitaf $RT 1 ; exit $RT; fi
                ;;
            *)
                echo ongeldig input argument
                exit 1
                ;;
        esac

        echo 'einde update_phase'
}
function filter_staging_tabel
{
 	RT=0
	echo 'in filter_staging_tabel'
 	

        select_active_filter_query="export to filters.del of del modified by nochardel select rubriekId || ' ' || filtersubId from audit.filter where actief = 1 order by rubriekId, filterSubId"
        db2 -x ${select_active_filter_query}
        RT=$?
        TEKST="Het exporten van de actieve filters is mislukt"
        if  [ "$RT" -gt 1 ] ; then logmessage "$TEKST" null 1;  sluitaf $RT; exit $RT; fi
    
        while read rubriekId filtersubId
        do
                
            from_clause=" from AUDIT.' || DSI_TABNAAM || '$VERSIE_SUFFIX where server_naam = ''$HOST'' and instance_naam = ''$DB2INSTANCE'' and audit_runtime = ''$AUDITRUN_TS'' and ' || where_clause from audit.rubrieken r join audit.filter f on f.rubriekId = r.rubriekId where f.rubriekId = ${rubriekId} and f.filtersubId = ${filtersubId}"    
            generate_select_query="select 'select rtrim(cast(count(*)as char(10))) ${from_clause}"
    
            COUNT_QUERY=`db2 -x ${generate_select_query}`
            RT=$?
            TEKST="Het genereren van de count query voor rubriekId ${rubriekId} en filterSubId ${filtersubId} is mislukt"
            if  [ "$RT" -gt 1 ] ; then logmessage "$TEKST" null 1;  sluitaf $RT; exit $RT; fi
    
            echo "Count query: ${COUNT_QUERY}"
            COUNT=`db2 -x ${COUNT_QUERY}`
            RT=$?
            TEKST="Tellen van rijen voor rubriekId ${rubriekId} en filterSubId ${filtersubId} is mislukt"
            if  [ "$RT" -gt 1 ] ; then logmessage "$TEKST" null 1;  sluitaf $RT; exit $RT; fi
     
            if [[ $COUNT -gt 0 ]];then
                generate_delete_query="select 'delete ${from_clause}"
                DELETE_QUERY=`db2 -x ${generate_delete_query}`
                RT=$?
                TEKST="Het genereren van de delete query voor rubriekId ${rubriekId} en filterSubId ${filtersubId} is mislukt"
                if  [ "$RT" -gt 1 ] ; then logmessage "$TEKST" null 1;  sluitaf $RT; exit $RT; fi
    
                echo "Delete query: $DELETE_QUERY"
                db2 $DELETE_QUERY
                RT=$(($RT+$?))
                if  [ "$RT" -gt 1 ] ; then db2 rollback;  sluitaf $RT 1 ; exit $RT; fi

                COMMENT="${COUNT} Records verwijderd voor  rubriekId ${rubriekId} en filterSubId ${filtersubId}" 
                logmessage "$COMMENT"   $COUNT
            fi
        done < filters.del
        rm filters.del
        
	echo 'uit filter_staging_tabel'

	update_phase "filter_staging_tabel"

	return
}
function flush_buffer
{
 	RT=0
	# zorg dat de inhoud van de audit buffer naar de logfile wordt geschreven
	db2audit flush
	RT=$(($RT+$?))
	TEKST="Legen van audit buffer naar logfile middels flush is mislukt. Returncode: "$RT
	#
	if  [[ $RT -gt 0 ]]; then logmessage "$TEKST" null 1 ; sluitaf $RT; exit $RT; fi
	#
	return
}
function clear_workspace
{
	RT=0
	#Verwijder bestanden uit delasc directory. Delete bestanden ouder dan 1 jaar:
	cd $AUDITPATH/$DB2INSTANCE/delasc
	rm  -f $AUDITPATH/$DB2INSTANCE/delasc/*
	#
	#check of alle files echt weg zijn uit delasc dir, anders wordt data uit file opnieuw geladen
	cd $AUDITPATH/$DB2INSTANCE/delasc
	DIRCONTENT=`ls -lA | awk '{print $9}' | wc | awk '{print $1}'`
	if  [ "$DIRCONTENT" -gt 1 ]
	then
		TEKST="delasc directory bevat nog files van vorige run, audit verwerking stopt."
		print $TEKST
		logmessage "$TEKST" null 1
		RT=90
		sluitaf $RT
		exit $RT
	fi
	#
	#delete files met timestamp ouder dan 1 jaar
	cd $AUDITPATH/$DB2INSTANCE/delhist
	find ./ -name "*.del.*.gz" -type f -mtime +365 -exec rm -f {} \;
	#
	return
}
function clear_db2audit_archive
{
        #maak archive directory leeg
        cd $AUDITPATH/$DB2INSTANCE/archive
        rm -f db2audit.*.log.0.*
        # check of directory echt leeg
        DIRCONTENT=`ls -la | grep -i db2audit |awk '{print $9}' | wc | awk '{print $1}'`
        if  [ "$DIRCONTENT" -gt 0 ]
        then
                TEKST="archive directory bevat files van vorige run, audit verwerking stopt."
                print $TEKST
                logmessage "$TEKST" null 1
                RT=91
                sluitaf $RT
                exit $RT
        fi

}
function stage_audit_data
{
	RT=0
	TEMPS=/tmp/TMP.$(date +"%y-%m-%d-%H-%M-%S")

        STAG_QUERY_WHERE_CLAUSE=" where audit_runtime = '$AUDITRUN_TS' and server_naam = '$HOST' and instance_naam = '$DB2INSTANCE')"
	echo 'STAG_QUERY_WHERE_CLAUSE: '$STAG_QUERY_WHERE_CLAUSE

        RUBR_STAG_QUERY="select DSI_TABNAAM || '#' || query ||'#'|| rubrieknaam from table(audit.get_staging_queries_for_db2level("$DB2LEVEL"))"
        echo 'rubr_stag_query = ' $RUBR_STAG_QUERY

	db2 -x $RUBR_STAG_QUERY  > $TEMPS
	RT=$(($RT+$?))
	if  [ "$RT" -gt 1 ] ; then sluitaf $RT 1 ; exit $RT; fi

	while read line
	do
	    echo 'stage_audit_data, line: '$line
	    DSI_TABNAAM=` echo $line | awk -F"#" '{print $1}'`
	    DS1_DS2_STAG_QUERY_PART=` echo $line | awk -F"#" '{print $2}'`
	    RUBRIEKNAAM=` echo $line | awk -F"#" '{print $3}'`  
	    DS1_DS2_STAG_QUERY=$DS1_DS2_STAG_QUERY_PART$STAG_QUERY_WHERE_CLAUSE  

	    echo 'DS1_DS2_STAG_QUERY_PART: '$DS1_DS2_STAG_QUERY_PART
  	    echo 'dsi_tabnaam: '$DSI_TABNAAM
  	    echo 'staging_query: '$DS1_DS2_STAG_QUERY
  	    echo 'rubrieknaam: '$RUBRIEKNAAM 	 

            COUNT_QUERY="select rtrim(cast(count(*)as char(10))) from AUDIT.$DSI_TABNAAM$VERSIE_SUFFIX where server_naam = '$HOST' and instance_naam = '$DB2INSTANCE' and audit_runtime = '$AUDITRUN_TS' "
	    echo 'stage_audit_date, COUNT_QUERY: '$COUNT_QUERY
  	    COUNT=$(db2 -x $COUNT_QUERY )
	    RT=$(($RT+$?))
	    echo 'aantal te stagen records in dsi tabel: '$COUNT	
	    if  [ "$RT" -gt 1 ] ; then sluitaf $RT ; exit $RT; fi

	    if [ $COUNT -gt 0 ]
	    then
	        #voer staging query uit 
	        db2  $DS1_DS2_STAG_QUERY
	        RT=$(($RT+$?))
	        echo 'RT na DS1_DS2_STAG_QUERY: '$RT

	        if  [ "$RT" -gt 0 ]
	        then
		    db2 rollback
		    TEKST='records naar ds2 '$RUBRIEKNAAM' tabel schrijven mislukt. Returncode: '$RT
		    logmessage "$TEKST" $COUNT 1
		    sluitaf $RT 1
	        else
		    # insert in ds2_xxx tabel is gelukt
		    TEKST='records succesvol van dsi naar ds2 '$RUBRIEKNAAM' tabel geschreven'
		    logmessage "$TEKST" $COUNT
		    # verwijderen verwerkte records uit dsi_xxx tabel
                    db2 "delete from AUDIT.$DSI_TABNAAM$VERSIE_SUFFIX where server_naam = '$HOST' and instance_naam = '$DB2INSTANCE' and audit_runtime = '$AUDITRUN_TS' "
		    RT=$(($RT+$?))
		    TEKST='delete van succesvol verwerkte records uit '$DSI_TABNAAM' tabel mislukt. Returncode: '$RT
		    if  [ "$RT" -gt 1 ] ; then db2 rollback; db2 connect reset ; logmessage "$TEKST" $COUNT 1 ; sluitaf $RT 1 ; exit $RT; fi

		    TEKST='verwerkte records succesvol verwijderd  uit dsi '$RUBRIEKNAAM' tabel'
		    logmessage "$TEKST" $COUNT	
	        fi
	    else
	        TEKST='geen records in dsi '$RUBRIEKNAAM' tabel aanwezig om over te zetten naar ds2'
	        logmessage "$TEKST" $COUNT
	    fi	
	done < $TEMPS
	rm $TEMPS

	update_phase "stage_audit_data"

	return
}
function archive_logfiles
{
 	RT=0
 	if [[ $# -eq 0 ]];then
   	    print "Geen logtarget als argument opgegeven. Toegestane logtargets zijn node of database. Auditverwerking stopt."
	    RT=99
	    db2 rollback
	    sluitaf $RT
	    exit $RT
	fi

	LOGTARGET=$1

        case $LOGTARGET in
            "node") 
                FILE_FILTER='db2audit.instance.log.'
                COLNR=\$4
                ;;
            "database")
                FILE_FILTER='db2audit.db.'
                COLNR=\$3
                ;;
            *)
                echo "Invalid logtarget"
                exit 101
                ;;
        esac

	cd $AUDITPATH/$DB2INSTANCE/log
	ELEMENT='BLURP'
	for i in `ls -la | grep -i $FILE_FILTER | grep -v bu_db2audit |awk '{print $9}' `
	do
	    ELEMENT=` echo $i |sed -e 's/\./ /g' | awk '{print '$COLNR'}'`  
	    db2audit archive $LOGTARGET $ELEMENT 
	    RT=$(($RT+$?))
	    TEKST="Archiveren van "$LOGTARGET" met naam "$ELEMENT" mislukt. Returncode: "$RT
	    if  [ "$RT" -gt 0 ] ; then logmessage "$TEKST" null 1 ; sluitaf $RT; exit $RT;  fi

	    TEKST="logfile "$i" behorende bij "$LOGTARGET" "$ELEMENT" gearchiveerd"
	    logmessage "$TEKST"
	done
	return
}
function extract_archive
{
 	RT=0
 	if [[ $# -eq 0 ]];then
   	    print "Geen archive prefix als argument opgegeven. Auditverwerking stopt."
	    RT=98
	    db2 rollback
	    sluitaf $RT
	    exit $RT
	fi
	PREFIX=$1
	cd $AUDITPATH/$DB2INSTANCE/archive
	for i in `ls -la | grep -v .gz | grep -i $PREFIX |awk '{print $9}' `
	do
	    db2audit extract delasc to $AUDITPATH/$DB2INSTANCE/delasc from files $AUDITPATH/$DB2INSTANCE/archive/$i
	    RT=$(($RT+$?))
	    if  [ "$RT" -gt 0 ] ; then db2 rollback; sluitaf $RT ; exit $RT; fi

	    TEKST="archive "$i"  geextraheerd"
	    logmessage "$TEKST"
	done
	return	
}
function backup_delasc_files
{
	RT=0
 	TEMPQ=/tmp/TMP.$(date +"%y-%m-%d-%H-%M-%S")
        QRUBR_QUERY="select delplusfilenaam from AUDIT.RUBRIEKEN"
        echo 'Rubrieken_query = ' $QRUBR_QUERY
        db2 -x $QRUBR_QUERY  > $TEMPQ
	RT=$(($RT+$?))

	if  [ "$RT" -gt 1 ] ; then sluitaf $RT ; exit $RT; fi

	while read delplusfile
	do
	    #plaats bestanden in delasc directory in gezipt formaat in delhist. Delete bestanden ouder dan 1 jaar:
	    cd $AUDITPATH/$DB2INSTANCE/delhist
	    #kopieer delasc files naar delhist
	    cp $AUDITPATH/$DB2INSTANCE/delasc/${delplusfile} $AUDITPATH/$DB2INSTANCE/delhist
	    # zip alle files die niet extensie gz hebben
	    cd $AUDITPATH/$DB2INSTANCE/delhist
	    for unzippeddelplusfile in `ls -la | grep -v .gz | grep ${delplusfile} |awk '{print $9}' | sort `
	    do
                ts=`echo ${AUDITRUN_TS} | sed 's/-//g' | sed 's/\.//g'`
	        FILE_SUFFIX=".${ts}.gz"
    	        echo "FILE_SUFFIX: "$FILE_SUFFIX

    	        gzip -f -N  -S $FILE_SUFFIX ${unzippeddelplusfile}
    	        RT=$(($RT+$?))
    	        echo "na gzip"  

    		if  [[ $RT -gt 0 ]] ; then
    		    TEKST="Zippen van files in delasc directory mislukt. Returncode: "$RT
    		    logmessage "$TEKST" null 1
    		    sluitaf $RT
    		    exit $RT 
    		else
    		    TEKST=${delplusfile}" file gezipt naar "${unzippeddelplusfile}$FILE_SUFFIX
    		    logmessage "$TEKST" 
    		fi	
            done
	done < $TEMPQ
	rm $TEMPQ
	#check of auditlobs file gevuld is, zoja, backup deze file
	if [[ -s $AUDITPATH/$DB2INSTANCE/delasc/auditlobs ]]  
        then
	    echo "file has data."
	    cp $AUDITPATH/$DB2INSTANCE/delasc/auditlobs $AUDITPATH/$DB2INSTANCE/delhist
	    # zip alle files die niet extensie gz hebben
	    cd $AUDITPATH/$DB2INSTANCE/delhist
	    FILE_SUFFIX=".$(date +'%Y%m%d%H%M%S').gz"
	    gzip -f -N  -S $FILE_SUFFIX auditlobs
	    RT=$(($RT+$?))
	    if  [[ $RT -gt 0 ]] ; then
	        TEKST="Zippen van auditlobs file in delasc directory mislukt. Returncode: "$RT
	        logmessage "$TEKST" null 1
	        sluitaf $RT
	        exit $RT 
	    else
	        TEKST="auditlobs file gezipt naar auditlobs"$FILE_SUFFIX
	        logmessage "$TEKST" 
	    fi			   
	fi
	return
}
function verrijk_en_snoei_delasc_files
{
    echo 'enter verrijk_en_snoei_delasc_files'
    RT=0

    DBMS_VERSIE2=`echo $DBMS_VERSIE | awk '{print $1"_"$2}'` 
    PREFIXSTRING='"'$SERVER'","'$DB2INSTANCE'","","'$DBMS_VERSIE2'","'$AUDITRUN_TS'",' 	
    echo 'PREFIXSTRING:  ' $PREFIXSTRING

    #database=`ls -l $AUDITPATH/$DB2INSTANCE/archive | grep "db2audit.db." | cut -d '.' -f 3`  
    rubrieken_query="select delfilenaam, r.delplusfilenaam from audit.rubrieken r "
    echo Rubrieken query: ${rubrieken_query}

    db2 -x ${rubrieken_query} > rubrieken.txt
    RT=$(($RT+$?))
    if  [ "$RT" -gt 1 ] ; then sluitaf $RT ; exit $RT; fi
     
    while read delfile delplusfilenaam
    do
        echo delfile: ${delfile} 
        echo delplusfilenaam: ${delplusfilenaam}

        # Count the number of lines in the delasc file
        delasc_count=`wc -l $AUDITPATH/$DB2INSTANCE/delasc/${delfile} | awk '{print $1}'`

        TEKST="Totaal aantal regels in ${delfile}"
        logmessage "${TEKST}" ${delasc_count}
    
        filter_query="select f.description || ';' || f.filter || ';' || r.DELPLUSFILENAAM from audit.category_filters f join audit.rubrieken r on r.rubriekId = f.rubriekId where delfilenaam = '${delfile}'"
        echo Filter query: ${filter_query}

        db2 -x "${filter_query}" > filter.txt 
        RC=$?

        # Return code 1 only means no rows are returned. This return code can be ignored
        if  [ "$RC" -gt 1 ]; then RT=$(($RT+$RC)); fi
        if  [ "$RT" -gt 1 ] ; then sluitaf $RT ; exit $RT; fi

        # Make sure the filter.txt file exists
        touch filter.txt
    
        # Build a sed filter file to execute all filters at once
        while read line
        do
            description=`echo ${line} | cut -f 1 -d ';'`
            filter=`echo ${line} | cut -f 2 -d ';'`
            echo "    description: ${description}"
            echo "    filter: ${filter}"
    
            filter_count=`grep ${filter} $AUDITPATH/$DB2INSTANCE/delasc/${delfile} | wc -l`
    
            echo "    Voor filter ${description} zullen er ${filter_count} rijen worden verwijderd uit ${delfile}"
            TEKST="Records verwijderd tijdens filteren delasc bestand ${delfile} voor filter ${description}"
            logmessage "${TEKST}" ${filter_count} 
    
            # Add this filter to the list of filters
            echo "/${filter}/d" >> ${delfile}_sed_filter
    
        done < filter.txt
    
        # Add the prefix information to the file with filters
        echo "s/^/${PREFIXSTRING}/" >> ${delfile}_sed_filter
        
        echo Alle filters voor bestand ${delfile} toegevoegd aan lijst met filters
    
        if [ -f  ${delfile}_sed_filter ]
        then 
            # Make the filter list executable
            chmod +x ${delfile}_sed_filter
     
            # Execute all filters for file ${delfile}
            echo Voer filters uit voor bestand ${delfile}
            sed -f ${delfile}_sed_filter $AUDITPATH/$DB2INSTANCE/delasc/${delfile} > $AUDITPATH/$DB2INSTANCE/delasc/${delplusfilenaam}
            RT=$(($RT+$?))
            if  [ "$RT" -gt 1 ] ; then sluitaf $RT ; exit $RT; fi
    
            # Remove the file with filters
            rm ${delfile}_sed_filter
    
            echo Bestand ${delfile} gefilterd, verrijkt en gekopieerd naar ${delplusfilenaam}
        else 
            # No filters to apply. This sitution should not occor. Raise an error
            echo Het bestand met sed filters kon niet worden gevonden. 
            exit 1       
        fi
        
        # For the context and execute files we add line numbers to the file. These linenumber will be part of the primary key in the DSI tables
        # We do this for the plus files, since they contain much less lines after the filtering process
        if [ ${delfile} = "context.del" ] || [ ${delfile} = "execute.del" ]
        then
            # Add a line number to the start of each line
            echo Voeg regelnummers to aan bestand ${delfile}
    
            mv $AUDITPATH/$DB2INSTANCE/delasc/${delplusfilenaam} $AUDITPATH/$DB2INSTANCE/delasc/${delplusfilenaam}_tmp
            awk '{printf "\"%d\",%s\n", NR, $0}' < $AUDITPATH/$DB2INSTANCE/delasc/${delplusfilenaam}_tmp > $AUDITPATH/$DB2INSTANCE/delasc/${delplusfilenaam}
            rm $AUDITPATH/$DB2INSTANCE/delasc/${delplusfilenaam}_tmp
        fi

        echo Klaar met het filteren en verrijken van ${delfile}

        rm filter.txt
    
    done < rubrieken.txt
    
    rm rubrieken.txt
 
    echo 'exit verrijk_en_snoei_delasc_files'
    return
}

function load_extracted_data
{
	RT=0
 	TEMPR=/tmp/TMP.$(date +"%y-%m-%d-%H-%M-%S")
        RUBR_QUERY="select rubrieknaam, delplusfilenaam, dsi_tabnaam, contains_lobs from AUDIT.RUBRIEKEN "
        db2 -x $RUBR_QUERY  > $TEMPR
	RT=$(($RT+$?))
	if  [ "$RT" -gt 1 ] ; then sluitaf $RT 1 ; exit $RT; fi

	while read line
	do
	    echo 'loadExtractedData, line: '$line
	    RUBRIEKNAAM=` echo $line | awk '{print $1}'`
	    DELPLUSFILENAAM=` echo $line | awk '{print $2}'`
	    DSI_TABNAAM=` echo $line | awk '{print $3}'`
	    DSI_TABNAAM=$DSI_TABNAAM$VERSIE_SUFFIX 
            CONTAINS_LOBS=` echo $line | awk '{print $4}'`

            echo 'rubrieknaam: '$RUBRIEKNAAM
  	    echo 'delplusfilenaam: '$DELPLUSFILENAAM
  	    echo 'dsi_tabnaam: '$DSI_TABNAAM   
            echo 'contains lobs: '${CONTAINS_LOBS}
            
            if [ ${CONTAINS_LOBS} = "1" ]
            then
                echo Transfer data using import 
                data_transfer_command="import FROM $AUDITPATH/$DB2INSTANCE/delasc/$DELPLUSFILENAAM OF DEL LOBS FROM $AUDITPATH/$DB2INSTANCE/delasc/ MODIFIED BY DELPRIORITYCHAR LOBSINFILE ALLOW WRITE ACCESS COMMITCOUNT 10000 INSERT_UPDATE INTO AUDIT.$DSI_TABNAAM"

            else
                echo Transfer data using load 
                data_transfer_command="LOAD CLIENT FROM $AUDITPATH/$DB2INSTANCE/delasc/$DELPLUSFILENAAM OF DEL MODIFIED BY DELPRIORITYCHAR INSERT INTO AUDIT.$DSI_TABNAAM NONRECOVERABLE"
            fi

            echo ${data_transfer_command}
            db2 -x ${data_transfer_command}
            RC=$?

            # Return code 2 only means no rows are returned. This return code can be ignored
            if  [ "$RC" -gt 2 ]; then RT=$(($RT+$RC)); fi

	    TEKST="Laden van comma delimited file "$DELPLUSFILENAAM" in database mislukt. Returncode: "$RT
	    if  [ "$RT" -gt 0 ] ; then db2 rollback; logmessage "$TEKST" null 1 ; sluitaf $RT ; exit $RT; fi
	    db2 commit;
	    RT=$(($RT+$?))
	    TEKST="Laden van comma delimited file "$DELPLUSFILENAAM" middels commit na load actie is mislukt. Returncode: "$RT
	    if  [ "$RT" -gt 0 ] ; then db2 rollback ; logmessage "$TEKST" null 1 ; sluitaf $RT ; exit $RT ; fi

	    # haal cardinaliteit op van dsi tabel uit catalog tbv opstellen runstats commando
	    CARD_QUERY="select card from syscat.tables where tabschema = 'AUDIT' and tabname = '$DSI_TABNAAM' and type = 'T' "
	    #doe runstats op dsi tabel tbv performance op dsi tabel
 	    echo 'loadExtractedData,CARD_QUERY: '$CARD_QUERY 
	    CARD=$(db2 -x $CARD_QUERY)
	    RT=$(($RT+$?))
	    TEKST="Fout opgetreden bij bepalen cardinaliteit in catalog voor tabel AUDIT."$DSI_TABNAAM".Returncode: "$RT   
	    if  [ "$RT" -gt 1 ] ; then logmessage "$TEKST" null 1 ; sluitaf $RT 1 ; exit $RT; fi

	    RUNSTATS_COMMAND=''
	    if  [[ $CARD -lt 1000000 ]] ; then
		RUNSTATS_COMMAND="runstats on table AUDIT.$DSI_TABNAAM with distribution and detailed indexes all "
	    else
		RUNSTATS_COMMAND="runstats on table AUDIT.$DSI_TABNAAM with distribution and detailed indexes all tablesample system(10) "
	    fi
	    db2 $RUNSTATS_COMMAND
	    RT=$(($RT+$?))
	    TEKST="Fout opgetreden bij uitvoeren runstats op tabel AUDIT."$DSI_TABNAAM".Returncode: "$RT   
	    if  [ "$RT" -gt 1 ] ; then logmessage "$TEKST" null 1 ; sluitaf $RT 1 ; exit $RT; fi

            SEL_QUERY="select rtrim(cast(count(*)as char(10))) from AUDIT.$DSI_TABNAAM where server_naam = '$HOST' and instance_naam = '$DB2INSTANCE' and audit_runtime = '$AUDITRUN_TS' "
  	    echo 'loadExtractedData,SEL_QUERY: '$SEL_QUERY 
	    COUNT=$(db2 -x $SEL_QUERY)
	    RT=$(($RT+$?))
	    TEKST="Fout opgetreden bij telling van aantal records in tabel AUDIT."$DSI_TABNAAM".Returncode: "$RT   
	    if  [ "$RT" -gt 1 ] ; then logmessage "$TEKST" null 1 ; sluitaf $RT 1 ; exit $RT; fi
	    TEKST="records geladen in tabel "$DSI_TABNAAM
	    logmessage "$TEKST" $COUNT
	done < $TEMPR
	rm $TEMPR

	update_phase "load_extracted_data"

	return
}
function process_audit_data
{

        clear_workspace

	# zorg dat de inhoud van de audit buffer naar de logfile wordt geschreven
 	flush_buffer
	
	#archiveer de log files van de databases
	archive_logfiles 'database'

	#archiveer de log files van de instances
	archive_logfiles 'node'

	#extraheer de archive bestanden behorende bij de databases
	extract_archive 'db2audit.db.'

	#extraheer de archive bestanden behorende bij de instances
	extract_archive 'db2audit.instance.log.'

	#verrijk gextraheerde bestanden met audit runtime gegevens
        verrijk_en_snoei_delasc_files

	#maak een backup van de verrijkte, geextraheerde bestanden
	backup_delasc_files

	update_phase "process_audit_data"

        # Verwijder de nu volledig verwerkte audit bestanden uit de archive map
        # We verwijderen de archive bestanden pas nadat we vast hebben gelegd dat deze fase af is gerond. Dan pas weten we zeker dat we ze niet meer nodig hebben. 
        # TODO DVV: Uit commentaar halen nadat het getest is dat alles uit de bestanden is verwerkt
        #clear_db2audit_archive

	return
}
function clear_tables
{
	table_identifier=$1
	local version_suffix=$2
	sel_query="select ${table_identifier} from audit.rubrieken"
	echo ${sel_query}

	db2 -x ${sel_query} > tablenames
	RT=$(($RT+$?))
	TEKST="Ophalen ds_tabnames mislukt"
	if  [ "$RT" -gt 0 ]; then logmessage "$TEKST" null 1;  sluitaf $RT; exit $RT; fi

	while read tabname
	do
    	    echo "Opschonen ${ds_tabname}"
    	    count_query="select count(1) from audit.${tabname}${version_suffix} where AUDIT_RUNTIME='${AUDITRUN_TS}'"
    	    echo ${count_query}
    	    COUNT=$(db2 -x ${count_query} )
    	    echo "Er worden ${COUNT} rijen verwijderd uit audit.${tabname}${version_suffix}"
	
    	    delete_query="delete from audit.${tabname}${version_suffix} where AUDIT_RUNTIME = '${AUDITRUN_TS}'"
    	    echo ${delete_query}

    	    db2 -x ${delete_query}
    	    RT=$?
    	    TEKST="Verwijderen regels uit audit.${tabname}${version_suffix} voor herstart mislukt"
    	    if  [ "$RT" -gt 1 ]; then logmessage "$TEKST" null 1;  sluitaf $RT; exit $RT; fi
	
	done < tablenames
	rm tablenames
}
function populate_dwh_tables {

    TEKST="Start vullen van de DWH tabellen"
    echo ${TEKST}
    logmessage  "$TEKST" 

    sel_query="select dso_tabnaam || ' ' || dwh_tabnaam from audit.rubrieken"
    echo ${sel_query}
    
    db2 -x ${sel_query} > tablenames
    RT=$(($RT+$?))
    TEKST="Ophalen dso/dwh tabnames mislukt"
    if  [ "$RT" -gt 0 ]; then logmessage "$TEKST" null 1;  sluitaf $RT; exit $RT; fi
    
    while read dso_table dwh_table
    do
        echo "Overzetten data van ${dso_table} naar ${dwh_table}"
        count_query="select count(1) from audit.${dso_table}"
        COUNT=$(db2 -x ${count_query} )
        TEKST="Er worden ${COUNT} rijen overgezet naar ${dwh_table}"
        echo ${TEKST}
        logmessage "${TEKST}" ${COUNT}
    
        transfer_query="insert into audit.${dwh_table} (select * from audit.${dso_table})"
        echo "${transfer_query}"
    
        db2 -x "${transfer_query}"
        RT=$?
        TEKST="Overzetten data van ${dso_table} naar ${dwh_table} is mislukt"
        if  [ "$RT" -gt 1 ]; then logmessage "$TEKST" null 1;  sluitaf $RT; exit $RT; fi
    
    done < tablenames
    rm tablenames

    TEKST="Start legen van de DSO tabellen"
    echo ${TEKST}
    logmessage  "$TEKST"


    # De DWH tabellen zijn allemaal succesvol gevuld. Nu kunnen we de DSO tabellen leeg maken.
    clear_tables dso_tabnaam
    
    update_phase ready
}
#
### einde functies
#
#######################################################################################################
#
##
##-------------------------------------------------------------------------------------------------------------------------------------
## begin met de audit verwerking
##-------------------------------------------------------------------------------------------------------------------------------------
#
# log aan op database waar de auditgegevens in gelogd worden
doe_cmdb_connect
set_query_optimization
NU=$(date +"%Y-%m-%d-%H.%M.%S")

status_query="select phase || '#' || AUDITRUN_TS from audit.database_status where host = '${HOST}' and instance = '${DB2INSTANCE}'"
echo ${status_query}

result=$(db2 -x ${status_query} )
RT=$?

if [[ ${RT} -gt 1 ]]
then
    TEKST="Bepalen initiele status query voor host = ${HOST} and instance = ${DB2INSTANCE} mislukt"
    echo $TEKST
  #  logmessage "$TEKST" null 1;
    sluitaf $RT; exit $RT;  
fi

if [[ ${RT} -eq 1 ]]
then
    # Dit is de eerste keer dat we deze database verwerken, completed_phase wordt kunstmatig gezet
    completed_phase=ready
    AUDITRUN_TS=${NU}
else
    completed_phase=`echo ${result} | cut -f 1 -d '#'`
    run_ts=`echo ${result} | cut -f 2 -d '#'`

    echo completed_phase: ${completed_phase}
    echo run_ts: ${run_ts}
    echo "Last completed phase: ${completed_phase}"

    completed_phase=`echo ${completed_phase} | sed 's/ //g'`
 
    if [[ ${completed_phase} != 'ready' ]]
    then
        # We hebben hier te maken met een herstart
        TEKST="Herstart audit run voor host = '${HOST}' and instance = '${DB2INSTANCE}' met AUDITRUN_TS ${run_ts}"
        echo ${TEKST}
    #    logmessage "$TEKST" null 1
        AUDITRUN_TS=${run_ts}
    else 
        AUDITRUN_TS=${NU}
    fi
fi

echo AUDITRUN_TS: ${AUDITRUN_TS}

claim_audit_resources

logmessage "Auditverwerking gestart op $AUDITRUN_TS"


case ${completed_phase} in
    "ready")
        next_phase=process_audit_data
        ;;
    "process_audit_data")
        echo Herstart na voltooiing process_audit_data
        clear_tables dsi_tabnaam ${VERSIE_SUFFIX}
        next_phase=load_extracted_data
        ;;
    "load_extracted_data")
        echo Herstart na voltooiing load_extracted_data
	   # No actions required. We can apply every filter again
        next_phase=filter_staging_tabel

        ;;
    "filter_staging_tabel")
        echo Herstart na voltooiing filter_staging_tabel

        clear_tables dso_tabnaam 
        next_phase=stage_audit_data

        ;;
    "stage_audit_data")
        echo Herstart na voltooiing stage_audit_data
        echo "Er is iets mis gegaan bij het vullen van de DWH tabellen. Dit moet handmatig op worden gelost"
        exit 2
        ;;
    *) 
        echo "'${completed_phase}' niet herkend als fase"
        exit 2
        ;;
esac

current_phase=""

while true
do
    if [[ ${current_phase} == ${next_phase} ]]
    then
        echo infinte loop detected
        exit 1
    fi

    case ${next_phase} in
        "process_audit_data" )
            current_phase=process_audit_data
            process_audit_data
            next_phase=load_extracted_data
            ;;
        "load_extracted_data")
            current_phase=load_extracted_data
            load_extracted_data
            next_phase=filter_staging_tabel
            ;;
        "filter_staging_tabel")
            current_phase=filter_staging_tabel
            filter_staging_tabel
            next_phase=stage_audit_data
            ;;
        "stage_audit_data")
            current_phase=stage_audit_data
            stage_audit_data
            next_phase=complete
            ;;
        "complete")
            current_phase=complete
            populate_dwh_tables
            sluitaf $RETURN_KODE
            db2 terminate;


            exit 0

            ;;
        *) 
            echo Unexpected phase
            exit 10
            ;;
    esac
done

exit 0


