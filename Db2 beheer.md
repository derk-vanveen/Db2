# Backups

- Full
- Incremental → Vanaf laatste full backup
- Delta → Vanaf de laatste backup

![6f831f0c-1be1-4947-9220-ea0c7d8717d3.png](https://files.nuclino.com/files/f1be754e-f888-4b0c-8386-05eedcbe948a/6f831f0c-1be1-4947-9220-ea0c7d8717d3.png)

The **db2ckrst** utility can be used to query the database history and generate a list of backup image time stamps needed for an incremental restore. A simplified restore syntax for a manual incremental restore is also generated. It is recommended that you keep a complete record of backups, and use this utility only as a guide.

```
 db2ckrst -d <database> -t <timestamp>
```

## Backup statistics

[IDUG : Blogs : Understanding the DB2 LUW Backup Performance Statistics](https://www.idug.org/p/bl/et/blogaid=518 "IDUG : Blogs : Understanding the DB2 LUW Backup Performance Statistics")

```
2020-06-12-04.46.30.224970+120 E5072217A1893        LEVEL: Info
PID     : 7078128              TID : 13891          PROC : db2sysc 0
INSTANCE: db2inst              NODE : 000           DB   : ....
APPHDL  : 0-25154              APPID: *LOCAL.db2ipr03.200612024504
AUTHID  : ...                  HOSTNAME: ...
EDUID   : 13891                EDUNAME: db2agent (KV0MWPDB) 0
FUNCTION: DB2 UDB, database utilities, sqluxLogDataStats, probe:396
MESSAGE : Performance statistics
DATA #1 : String, 1383 bytes

Parallelism       = 5
Number of buffers = 10
Buffer size       = 16781312 (4097 4kB pages)
                                                                               Compr
BM#    Total      I/O      Compr     MsgQ      WaitQ      Buffers   kBytes    kBytes
---  --------  --------  --------  --------  --------    --------  --------  --------
000     83.37      2.11      6.22      0.00     74.97           5    184320    197102        28
001     83.10     10.40     62.15      0.00     10.14          30   1828864   1829138       274
002     83.10      8.95     61.45      0.00     12.25          53   1384448   1385123       675
003     83.10      1.87      9.30      0.00     71.57           3    327808    327842        34
004     83.10      1.60      6.51      0.00     74.61           1    217600    217600         0
---  --------  --------  --------  --------  --------    --------  --------  --------
TOT    415.78     24.95    145.64      0.00    243.56          92   3943040   3956806

MC#    Total      I/O                MsgQ      WaitQ      Buffers   kBytes
---  --------  --------            --------  --------    --------  --------
000     84.07     62.71               20.65      0.00          94   1491344
---  --------  --------            --------  --------    --------  --------
TOT     84.07     62.71               20.65      0.00          94   1491344
```

waitQ: time the edu processing the backup was idle. Als er een hele grote tablespace is, zal het proces voor die ene tablespace een lage waitq hebben en alle andere een hele hoge waarde voor waitQ.&#x20;

# Statistics

From idug 2019: EU19C15N.pdf from C15 - Steroids for the Optimizer - An Introduction to (Advanced) Statistics

[Db2 documentation](https://app.nuclino.com/t/b/75ff5d51-3dc2-40e0-919e-af2592a01e12?n) Statistics

+------------------------+-----------------------+
|**Situation**           |**Statistics**         |
+------------------------+-----------------------+
|Uniform distribution    |Basic statistics       |
|                        |                       |
|Independence            |                       |
|                        |                       |
|Same domain             |                       |
+------------------------+-----------------------+
|Non uniform distribution|Distribution statistics|
+------------------------+-----------------------+
|Correlation             |Column-group statistics|
+------------------------+-----------------------+
|Different domain        |Statistical views      |
+------------------------+-----------------------+

## Basic statistics

Basic statistics per table

- Number of rows (card)
- Number of pages with rows (npages)
- Total number of pages (fpages)

Basic statistics per column

- Number of distincs values in a column (colcard)
- Number of null values (numnulls)
- High value (high2key)
- Low value (low2key)
- Average length of a column (avgcollen)

## Distribution statistics

Frequency statistics

- N most frequent values and their count
- Good for equality predicates
- Default: N=10
- sysstat.coldist (type = 'F')

Quantiles

- Number of rows above or below a certain value
- Good for range predicates
- Default: N=20 (20 different values ranges per column)
- sysstat.coldist (Type = 'Q')

```
RUNSTATS ON TABLE mnicola.mytest
WITH DISTRIBUTION [ON COLUMNS...];
```

## Column group statistics

Required when correlation between columns is high.&#x20;

Indication: explain plan shows very low cardinality estimation or very high estimation for group by.&#x20;

- SYSSTAT.COLGROUPS 1 row per column group&#x20;
- SYSSTAT.COLGROUPSDIST Frequent values / quantiles&#x20;
- SYSSTAT.COLGROUPSDISTCOUNTS  Number of rows per freq. value / quantile

```sql
RUNSTATS ON TABLE mnicola.product
ON ALL COLUMNS
AND COLUMNS ( (Segment, Category, Subcategory), (...) )
WITH DISTRIBUTION;
```

Collect collect group statistics to provide the optimizer with more accurate information about the value combinations that actually occur in two or more columns together.&#x20;

In the RUNSTATS command you would specify ON ALL COLUMNS to collect regular statistics for all columns and then the AND COLUMNS clause can be used to specify one or multiple column groups.&#x20;

If you omit “ON ALL COLUMNS” then statistics are reset for all columns that you do not specify for the RUNSTATS command (except for those columns that are the first column in an index.)&#x20;

Limitations

- Distribution statistics are not collected for the column groups.&#x20;
- The Frequency Option and Quantile Option parameters are not supported for column groups. These parameters are supported for single columns.

**When to use column group statistics**

- Predicates on multiple correlated column of the same table
- Join predicates on multiple columns
- Group By clauses with multiple correlated columns

<br>

## Statistical views

- Statistics for complex relationships or predicates
- Statistics across multiple tables, especially joins

```sql
CREATE VIEW stat_sales_time AS
(SELECT t.* FROM daily_sales ds, time t WHERE ds.datekey = t.datekey);

ALTER VIEW stat_sales_time ENABLE QUERY OPTIMIZATION;

RUNSTATS ON VIEW mnicola.stat_sales_time WITH DISTRIBUTION...;
```

Query with aggregation

```
CREATE VIEW statv3 AS
(SELECT p.*, s.*
FROM daily_sales ds,
store s,
product p,
WHERE ds.storekey = s.storekey
AND ds.prodkey = p.prodkey);

ALTER VIEW statv3 ENABLE QUERY OPTIMIZATION;

RUNSTATS ON VIEW mnicola.statv3
ON ALL COLUMNS AND ON COLUMNS((region,segment))
WITH DISTRIBUTION;
```

## runstat commands

Collect statistics for table only:

```
RUNSTATS ON TABLE <schema>.<tablename>
```

&#x20;Collect statistics for indexes only on a given table

```
RUNSTATS ON TABLE <schema>.<tablename> FOR INDEXES ALL
```

Collect statistics for both table and its indexes

```
RUNSTATS ON TABLE <schema>.<tablename> AND INDEXES ALL
```

Collect statistics for table including distribution statistics:

```
RUNSTATS ON TABLE <schema>.<tablename> WITH DISTRIBUTION
```

Collect statistics for indexes only on a given table including extended index statistics

```
RUNSTATS ON TABLE <schema>.<tablename> FOR DETAILED INDEXES ALL
```

Collect statistics for table and its indexes including extended index and distribution statistics

```
RUNSTATS ON TABLE <schema>.<tablename> WITH DISTRIBUTION AND DETAILED INDEXES ALL
```

\
\


# Cur\_commit

```sql
select 
	CUR_COMMIT_DISK_LOG_READS, 
	CUR_COMMIT_TOTAL_LOG_READS, 
	CUR_COMMIT_LOG_BUFF_LOG_READS 
from table(MON_GET_TRANSACTION_LOG(-1))

```

# Rowsize of a table

```sql
CREATE OR REPLACE FUNCTION GetRowSize(tabschema VARCHAR(128), tabname VARCHAR(128))
RETURNS INTEGER
SPECIFIC GETROWSIZE READS SQL DATA DETERMINISTIC NO EXTERNAL ACTION
BEGIN
  DECLARE rowsize         INTEGER DEFAULT 0;
  DECLARE loblength       INTEGER; 
  DECLARE compression_mod INTEGER;
  
  SELECT CASE WHEN compression in ('B', 'V') THEN 2 ELSE 0 END 
    INTO compression_mod
    FROM SYSCAT.TABLES AS T 
	WHERE T.tabschema = getrowsize.tabschema 
	  AND T.tabname   = getrowsize.tabname;
	  
  FOR column AS  SELECT COALESCE(D.SOURCENAME, C.TYPENAME) AS TYPENAME, 
                        COALESCE(D.LENGTH, C.LENGTH) AS LENGTH, 
                        C.SCALE, C.NULLS, C.INLINE_LENGTH, D.METATYPE,
                        D.INLINE_LENGTH AS STRUCT_INLINE_LENGTH
                  FROM SYSCAT.COLUMNS AS C
                  LEFT OUTER JOIN SYSCAT.DATATYPES AS D
                               ON D.typeschema = C.typeschema 
                               AND D.typename = C.typename
                               AND D.typemodulename IS NULL
                               AND C.typeschema <> 'SYSIBM  '
                  WHERE C.tabschema = getrowsize.tabschema 
                    AND C.tabname   = getrowsize.tabname DO
    SET loblength = CASE WHEN inline_length <> 0 
                           THEN inline_length
                         WHEN metatype = 'R' THEN struct_inline_length 
                         WHEN typename IN ('CLOB', 'BLOB', 'DBCLOB') 
                           THEN CASE WHEN length <=       1024 THEN 68
                                     WHEN length <=       8192 THEN 92
                                     WHEN length <=      65536 THEN 116										 
                                     WHEN length <=     524000 THEN 140
                                     WHEN length <=    4190000 THEN 164
                                     WHEN length <=  134000000 THEN 196
                                     WHEN length <=  536000000 THEN 220
                                     WHEN length <= 1070000000 THEN 252
                                     WHEN length <= 1470000000 THEN 276
                                     WHEN length <= 2147483647 THEN 312
                                     ELSE raise_error('78000', 'LOB too long') END
                         WHEN typename IN ('LONG VARCHAR', 'LONG VARGRAPHIC')
                           THEN 20
                         WHEN typename = 'XML' THEN 80
                         ELSE 0 END;	
    SET rowsize = rowsize +
                  CASE TYPENAME 
                       WHEN 'SMALLINT'        THEN length + compression_mod
                       WHEN 'INTEGER'         THEN length + compression_mod
                       WHEN 'BIGINT'          THEN length + compression_mod
                       WHEN 'REAL'            THEN length + compression_mod
                       WHEN 'DOUBLE'          THEN length + compression_mod
                       WHEN 'DECFLOAT'        THEN length + compression_mod
                       WHEN 'DECIMAL'         THEN TRUNC(length / 2) + 1 + compression_mod
                       WHEN 'CHARACTER'       THEN length + compression_mod
                       WHEN 'VARCHAR'         THEN length + 4 - compression_mod
                       WHEN 'GRAPHIC'         THEN length * 2 + compression_mod
                       WHEN 'VARGRAPHIC'      THEN length * 2 + 4 - compression_mod
                       WHEN 'LONG VARCHAR'    THEN 24 - compression_mod
                       WHEN 'LONG VARGRAPHIC' THEN 24 - compression_mod
                       WHEN 'CLOB'            THEN loblength + 4 - compression_mod
                       WHEN 'BLOB'            THEN loblength + 4 - compression_mod
                       WHEN 'DBCLOB'          THEN loblength + 4 - compression_mod
                       WHEN 'XML'             THEN loblength + 3 - compression_mod
                       WHEN 'DATE'            THEN length + compression_mod
                       WHEN 'TIME'            THEN length + compression_mod
                       WHEN 'TIMESTAMP'       THEN length + compression_mod
                       ELSE CASE WHEN metatype = 'R' THEN loblength + 4 - compression_mod
                                 ELSE raise_error('78000', 'Unknown type') END
                   END +
                   CASE WHEN compression_mod = 0 AND NULLS = 'Y' THEN 1 ELSE 0 END;
  END FOR;
  IF compression_mod <> 0 THEN
    SET rowsize = rowsize + 2;
  END IF;
  RETURN rowsize;
END;
/

```

```sql
SELECT varchar(tabschema, 10), tabname, getrowsize(tabschema, tabname) as rowsize 
  FROM SYSCAT.TABLES
  ORDER BY tabname 
  FETCH FIRST 10 ROWS ONLY;

```

# HADR

- HADR Calculator
- HADR Simulator
- DB2 Log Scanner

# Deadlocks

db2evmon -path /data/db2inst1/NODE0000/SQL00001/MEMBER0000/db2event/db2detaildeadlock > /tmp/deadlocks.txt

# Bufferpool clean

pool\_lsn\_gap\_clns

pool\_drty\_pg\_steal\_clns

pool\_drty\_pg\_thrsh\_clns

# Privileges

Privileges on database and system level

```sql
select substr(AUTHORITY,1,30) as Authority
    , D_USER
    , D_GROUP
    , D_PUBLIC
    , ROLE_USER
    , ROLE_GROUP
    , ROLE_PUBLIC
    , D_ROLE
from table(auth_list_authorities_for_authid('<USER>','U'));
```

Object level privileges

```sql
SELECT * FROM SYSIBMADM.PRIVILEGES where authid = '<user>';
```

List users with privileges

```sql
select * from SYSIBMADM.AUTHORIZATIONIDS;
```

# Export to named pipe

```
mkfifo /tmp/mypipe1

values current timestamp;
!gzip -c < /tmp/mypipe1 > /target_folder/<file>.ixf.gz & ;
export to /tmp/mypipe1 of ixf select * from <table>;
values current timestamp;
```

# Large delete

```sql
BEGIN

DECLARE no_data SMALLINT DEFAULT 0;--
DECLARE commit_count SMALLINT DEFAULT 10000;--
DECLARE del_stmt VARCHAR(512);--
DECLARE CONTINUE HANDLER FOR NOT FOUND SET no_data = 1;--

SET del_stmt='delete from ( select * from CRG.SEPA_CRG_LOG where date(REQUEST_OFF_QUEUE) < current_date - 60 days fetch first '||CHAR(COMMIT_COUNT)||' rows only with ur)';--
PREPARE prepared_delete FROM del_stmt;--

set no_data=0;--
WHILE ( no_data=0 ) DO
        EXECUTE prepared_delete;--
        COMMIT;--
END WHILE;--

END;
```

# Lateral joins

[IDUG : Blogs : Lateral join](https://www.idug.org/p/bl/et/blogaid=809 "IDUG : Blogs : Lateral join")

Basically, we need to query the employee table and fetch just the 3 employees with the highest salary. If that is the only task, we can do it for a single department as easily as:

```sql
SELECT lastname, salary FROM emp e
WHERE e.workdept = 'department' ORDER BY salary DESC FETCH FIRST 3 ROWS ONLY;
```

where *department* stands for a given specific department. However, we would like to have it for every department and report also the department name. To make it work, we need to join the department table with the aforementioned table expression and refer to the department in the join. What if we try the naive solution expressed here:

```sql
SELECT workdept, deptname, lastname, salary FROM dept d,                                                 
(SELECT lastname, salary FROM emp e WHERE e.workdept = d.deptno
 ORDER BY salary DESC
 FETCH FIRST 3 ROWS ONLY);                    
ORDER BY deptno, salary DESC, lastname;
```

```sql
select
	....
from table T1
, table(select ... from T2 where T2.c1 = T1.c1 
        fetch first row only)
;
```

# SSL Encryption

Het doel van SSL is tweeledig

1. Authenticatie door middel van een certificaat
2. Het versleutelen van communicatie tussen beide partijen gebaseerd op symmetrische cryptografie.

&#x20;SSL kan voor verschillende communicatiestromen binnen Db2 worden gebruikt:&#x20;

1. Client- Server communicatie
2. Voor HADR
3. DRDA wrappers&#x20;

Alle implementaties werken op min of meer dezelfde manier. Als zodra de eerste werkt, is de rest ook gemakkelijk te implementeren.

## Basis encryptie

&#x20;SSL maakt gebruik van asymmetrische cryptografie. Bij deze wijze van informatieversleuteling, zijn er twee verschillende sleutels die bij elkaar horen: een voor vercijferen en een voor ontsleutelen van informatie. In tegenstelling tot de geheime sleutel is de publieke sleutel bedoeld om uitgewisseld te worden met degene met wie men wil communiceren. Met de publieke sleutel kan een bericht worden versleuteld. Dit bericht is alleen te ontcijferen met behulp van de geheime sleutel.

&#x20;Bij symmetrische encryptie wordt dezelfde sleutel gebruikt voor het versleutelen en ontcijferen van berichten. Er is dus maar een sleutel voor nodig.

&#x20;Het doel van SSL is het waarborgen van de vertrouwelijkheid van een bericht. Indien naast integriteit en authenticiteit ook vertrouwelijkheid gewenst is, kan de openbare sleutel in het certificaat van de ontvanger gebruikt worden om een document of een bericht te vercijferen of versleutelen. Dat levert twee (te combineren) toepassingen op:&#x20;

1. Vercijferen met de openbare sleutel van de ontvanger: alleen de ontvanger kan het bericht met zijn eigen geheime sleutel ontcijferen. Vertrouwelijkheid is daarmee gewaarborgd
2. Versleutelen met de geheime sleutel van de afzender. Het bericht is alleen te ontcijferen met de openbare sleutel van de afzender, waardoor de authenticiteit van de afzender vast staat.

&#x20;Om vertrouwelijkheid, integriteit en authenticiteit te waarborgen, dient dus tweemaal achtereenvolgens vercijferd te worden:&#x20;

-  Client controleert geldigheid van het certificaat met de openbare sleutel van de server aan de hand van de samenvatting en de publieke sleutel van de uitgever;
-  Client vercijfert bericht met de openbare sleutel van de server;
-  Client ondertekent het bericht met een samenvatting en vercijfert deze samenvatting met zijn eigen geheime sleutel;
-  Client verstuurt het bericht naar server;
-  Server controleert geldigheid van het certificaat met de openbare sleutel van de client aan de hand van de samenvatting en de openbare sleutel van de uitgever;
-  Server controleert geldigheid van de samenvatting met de openbare sleutel van client;
-  Server ontcijfert het bericht met zijn/haar geheime sleutel.

## &#x20;Certificaten

&#x20;In de vorige paragraaf is al gesproken over certificaten. De inhoud van certificaten en hoe ze werken staat verder beschreven in de rest van dit hoofdstuk.

&#x20;Een certificaat bevat:&#x20;

-  Geregistreerde naam van de eigenaar c.q. certificaathouder;
-  Publieke sleutel c.q. openbare sleutel van de eigenaar c.q. certificaathouder;
-  Geldigheidsperiode van het certificaat;
-  Identiteit van de uitgever c.q. certificaatautoriteit van het certificaat;
-  Locatie van de 'Certificate Revocation List' (bij de uitgever van het certificaat);
-  Samenvatting van bovenstaande gegevens, aangemaakt door een hashfunctie, en vervolgens vercijferd met de geheime sleutel van de uitgever c.q. certificaatautoriteit. Dit wordt een waarmerk of digitale handtekening genoemd en dient om de geldigheid c.q. authenticiteit van bovenstaande gegevens te waarborgen.

&#x20;Waarborgen authenticiteit c.q. geldigheid van een certificaat:&#x20;

-  Ontvanger van het certificaat berekent zelf de samenvatting van bovenstaande gegevens met behulp van de gebruikte hashfunctie;
-  Ontvanger vraagt de openbare sleutel van de uitgever op ;
-  Ontvanger ontcijfert de ontvangen samenvatting in het certificaat met behulp van de openbare sleutel van de uitgever;
-  Ontvanger vergelijkt of beide samenvattingen overeenstemmen (bij verschil is het ontvangen certificaat na uitgifte aangepast en niet meer authentiek en geldig).

&#x20;Er zijn drie soorten certificaten&#x20;

1. Root certificaat
2. Tussen (intermediate) certificaat
3. SSL certificaat

Deze drie typen certificaten kunnen samen een keten vormen. Een SSL certificaat is ondertekend door een intermediate certificaat. Het intermediate certificaat is eventueel weer ondertekend door een ander intermediate certificaat, of een root certificaat. Het root certificaat is niet ondertekend door een ander certificaat.&#x20;

## Validatieketen van certificaten

&#x20;Een certificaat wordt vertrouwd als er een sluitende keten van certificaten is. Zo kan een tot nog toe onbekende server worden vertrouwd als op basis van de keten van certificaten blijkt dat de integriteit van de server wordt gegarandeerd.

&#x20;Stel dat een webserver het certificaat achmea.root.cer vertrouwd en dat het certificaat op een server is ondertekend door intermediate certificaat achmea.ota.cer. De webserver heeft in dit geval geen mogelijkheid om het SSL certificaat op de server te valideren; er is geen volledige keten van certificaten. De server wordt in dit geval niet vertrouwd en er kan geen verbinding op worden gebouwd.&#x20;

Wanneer de server echter zowel het SSL certificaat en het achmea.ota.cer certificaat bevat, kan de webserver de authenticiteit wel vaststellen. De keten van certificaten is volledig:&#x20;

-  Het SSL certificaat van de server is ondertekend door achmea.ota
-  Achmea.ota.cer is ondertekend door achmea.root.cer dat op de webserver staat
-  Achmea.root.cer wordt vertrouwd door de webserver.

## opbouwen versleutelde communicatie

SSL gebruikt zowel symmetrische als asymmetrische encryptie. Het SSL certificaat van de server bevat zowel een publieke als een geheime sleutel. De sleutel die uiteindelijk gebruikt wordt voor de sessie is symmetrisch.&#x20;

1.  **Server** stuurt een kopie van zijn publieke sleutel.
2.  **Client** maakt een symmetrische sleutel aan versleuteld deze met de asymmetrische sleutel van de server en stuurt dit naar de server.
3.  **Server** ontcijfert de symmetrische sleutel van de client met behulp van zijn geheime sleutel..
4. &#x20;**Server** en **Client** gebruiken nu de symmetrische sleutel voor versleutelen en ontcijferen van het verkeer. Het gebruik van symmetrische encryptie is veel minder CPU intensief in gebruik. Deze, iets minder veilige, manier van encryptie wordt alleen gebruikt voor de duur van een sessie. Iedere sessie heeft zijn eigen symmetrische sleutel.

## &#x20;inrichting van ssl voor db2 servers&#x20;

&#x20;Voor onze databases moeten we een keuze maken welk type certificaat er wordt gebruikt. Er zijn twee opties:&#x20;

1. Zelf ondertekende certificaten
2.  Gebruik maken van een certificaatautoriteit&#x20;

Afhankelijk van het gekozen type certificaat is het beheer voor de partijen die met de database communiceren.&#x20;

## Zelf ondertekende certificaten&#x20;

Zelf ondertekende certificaten zijn meer werk voor de beheerders van de clients.

&#x20;Certificaten gaan om vertrouwen. Wanneer je werkt met een zelf ondertekend certificaat zeg je: “Ik ben wie ik ben, omdat ik dat zelf zeg”. Je laat het aan de client over om te besluiten of ze dit daadwerkelijk doen. Wanneer de client jou vertrouwt moeten ze jouw certificaat opnemen in hun truststore als root certificaat.

&#x20;Iedere keer dat een certificaat verloopt, moeten alle clients het certificaat opnieuw importeren.

## &#x20;Gebruik certificaatautoriteit

&#x20;Deze paragraaf is onder voorbehoud, nog niet getest. Conclusies op basis van ibm support: “It is needed to enable SSL support at DB2 server side; Enable SSL support in the JVM. That means to enable WAS security and import DB2 signer certificate to WAS trust store.”

&#x20;Bij het gebruik van certificaatautoriteit (CA) staat iemand anders voor je in dat dat jij zegt wie je bent waar is. &#x20;

Je stuurt een verzoek tot ondertekening van een certificaat naar deze afdeling en zei kunnen jouw verzoek ondertekenen met bijvoorbeeld het intermediate.cer certificaat. Alle clients die het intermediate.cer certificaat vertrouwen, vertrouwen nu ook jouw certificaat en daarmee je database.

&#x20;De beheerder van de client hoeft dus niet jouw individuele certificaat te vertrouwen. Het certificaat dat is gebruikt om jouw certificaat te ondertekenen is voldoende. Hetzelfde geldt ook bij het vervangen van een verlopen certificaat. Wanneer het bovenliggende certificaat niet is veranderd, hoeft de client niets te doen om jouw nieuwe certificaat te vertrouwen.

## &#x20;Beheer certificaten

&#x20;Certificaten hebben een beperkte geldigheid. Voor het verstrijken van de einddatum moet het certificaat zijn vervangen. Zodra het certificaat is verlopen is er geen SSL communicatie meer mogelijk. Clients die zijn ingericht voor SSL kunnen nu geen verbinding meer opbouwen.

&#x20;**N.B.**&#x20;

1. **Succesvol gebruik van SSL valt of staat met het monitoren van de geldigheid van certificaten en deze op tijd vervangen.**
2. **Na het vervangen van een certificaat is altijd een herstart van de database nodig om het nieuwe certificaat te laden**

## Zelf ondertekende certificaten

&#x20;Wanneer je zelf ondertekende certificaten gebruikt kan je zelf de geldigheid kiezen. Hierbij moet je een afweging maken tussen hoeveel werk het is om een certificaat te vervangen en hoe belangrijk het versleutelen van de communicatie tussen client en database is.

&#x20;**N.B.** bij het vervangen van een zelf ondertekend certificaat moeten ook alle certificaten op de clients worden vervangen.

## Certificaatautoriteit (CA)

&#x20;Bij certificaten ondertekend door een certificaatautoriteit heb je geen invloed op de geldigheid van het certificaat; deze wordt gepaald door de ondertekenende autoriteit. Het is met name belangrijk om op tijd een nieuw certificaat aan te vragen.

&#x20;Wanneer het intermediate certificaat niet is gewijzigd voor het nieuwe certificaat hoeven er op de client geen wijzigingen door te worden gevoerd om het nieuwe certificaat te accepteren.

## Gebruik openssl

```
# Genereer een private key
openssl genrsa -aes256 -out <server>.unix.corp.key 2048

# Genereer een certificate request op basis van de private key
openssl req -new -key <server>.unix.corp.key -config db2ssl_conf.cnf -out <server>.unix.corp.csr

cat db2ssl_conf.cnf
[req]
default_bits=2048
distinguished_name=req_distinguished_name
prompt=no
req_extensions=v3_req
[req_distinguished_name]
C=NL
ST=<provincie>
L=<stad>
O=<Organisatie>
OU=<Organisatie Unit>
CN=<Common name, url of applicatie naam>

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 =<server>.unix.corp

# Controleer de keten. Alle drie de onderstaande commando's moeten hetzelfde resultaat geven
openssl rsa -noout -modulus -in usa30154.unix.corp.key -noout | openssl sha256
openssl req -noout -modulus -in usa30154.unix.corp.csr -noout | openssl sha256
openssl x509 -noout -modulus -in usa30154.unix.corp.cer | openssl sha256

Zet het geheel om naar pkcs12 formaat, wat db2 herkent
openssl pkcs12 -export -in <server>.unix.corp.cer -inkey <server>.unix.corp.key -out <server>.unix.corp.p12 -name "<server>.unix.corp"

```

## randvoorwaarden Db2

Om succesvol gebruik te maken van SSL moet aan twee voorwaarden worden voldaan:

-  Geen gebruik van connection concentration
-  Het correct instellen van dynamic library loading voor de benodigde tooling

### Connection concentration

Het gebruik van SSL is niet mogelijk in combinatie met connection concentration. Connection concentration wordt gebruikt wanneer max\_connections > max\_coordagents.

Connection concentration moet worden uitgezet voordat SSL wordt aangezet.

### Shared libraries

Er wordt met iedere versie van Db2 een versie van gskit opgeleverd, net als met Spectrum Protect (tsm). Deze versies zijn vaak niet compatible met elkaar. Om te zorgen dat op runtime de juiste shared libraries worden geladen moet het library path van de instance aan worden gepast.

Maar als instance owner het bestand \~/.kshrc aan met onderstaande twee regels.

```shell
export PATH=$HOME/sqllib/gskit/bin:$PATH
# Voor unix/aix
export LIBPATH=$HOME/sqllib/lib64/gskit:$LIBPATH
# Voor Linux
export LD_LIBRARY_PATH=$HOME/sqllib/lib64/gskit:$LIBPATH
```

# Linux authorizatie met PAM

[pam.d\_db2\_origineel.txt](https://files.nuclino.com/files/cd055533-f87c-4207-9b70-257b477ad814/pam.d_db2_origineel.txt)
