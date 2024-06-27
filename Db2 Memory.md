<br>

![Db2\_memory\_model.png](https://files.nuclino.com/files/2e93a457-bc15-4198-a3a4-eabb42c9b21c/Db2_memory_model.png)

Opbouw van geheugen componenten

| **Instance memory**  |                  |                  |
| -------------------- | ---------------- | ---------------- |
| mon\_heap\_sz        |                  |                  |
| java\_heap\_sz       |                  |                  |
| audit\_buf\_sz       |                  |                  |
| sheapthres           |                  |                  |
| aslheapsz            |                  |                  |
| fcm\_num\_buffers    |                  |                  |
| **appl\_memory **    |                  |                  |
|                      | applheapsz\*     |                  |
|                      | stat\_heap\_sz\* |                  |
|                      | stmtheap         |                  |
| **database\_memory** |                  |                  |
|                      | **dbheap\***     |                  |
|                      |                  | catalogcache\_sz |
|                      |                  | logbufsz         |
|                      | locklist         |                  |
|                      | pckcachesz       |                  |
|                      | sheapthres\_shr  |                  |
|                      | util\_heap\_sz\* |                  |
|                      | bufferpools      |                  |

\* Valt terug op instance memory indien nodig

# Sorts

Sort overflows

```sql
select 
	SORT_HEAP_ALLOCATED,
	SORT_HEAP_TOP,
	SORT_SHRHEAP_ALLOCATED,
	SORT_SHRHEAP_TOP,
	SORT_OVERFLOWS,
	SUBSTR(STMT_TEXT, 1, 100),
	ACTIVITY_TYPE,
	APPLICATION_HANDLE
from table(MON_GET_ACTIVITY(null, -2))
where sort_overflows > 0
with ur;
```

```
select
	ACTIVE_SORTS,
	ACTIVE_HASH_JOINS,
	ACTIVE_SORTS_TOP,
	ACTIVE_SORT_CONSUMERS_TOP,
	SORT_CONSUMER_HEAP_TOP, --Individual private sort heap consumer high watermark
	SORT_CONSUMER_SHRHEAP_TOP, -- Individual shared sort heap consumer high watermark monitor element
	TOTAL_SORTS,
	SORT_OVERFLOWS,
	SORT_HEAP_ALLOCATED,
	SORT_HEAP_TOP,
	SORT_SHRHEAP_ALLOCATED, --Total amount of shared sort memory allocated in the database. 
	SORT_SHRHEAP_TOP -- Sort share heap high watermark monitor element
from table(MON_GET_DATABASE(-2))
where sort_overflows > 0
with ur;
```

<br>
