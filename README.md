# Platform_Engg - SQL data warehouse geo Sync
Currently SQL data warehouse does not have geo sync with less than 8 hours RPO, with this script you can maintain 15mins RPO


Summary :

To adhere business continuity(RPO 15 mins) with SQL dataware house we have created Sql_dw_Geo_Sync custom tool. 
Currently SQL Data Warehouse does not support 15 mins RPO by Azure frame work. 
If any mass outage, then this could lead to data loss for any SQL dw.

Problem Statement :

In our system, we are using SQL Dw which is not support Geo Sync by azure framework with RPO 15 mins . 
We can only create Azure restore point with 8 hours RPO. If there is any data center down then we may loose minimum 8 hours transactional data.

Solution : 

To solve the problem we have created custom tool which will make the DB sync and reduce the RPO to 15 mins. Tool is helping us to create custom restore point every 15 mins(on Primary) and deleting 3 hours old restore point to save the cost. 
Every .5/1/2/4/n hours we are restoring the DR DB with snapshot. Which will control max data loss to 15 mins(BCDR RPO 15 mins).

Steps :
Algo

{            BackUp Primary:
              15 mins create the restore point(configurable can be 5 mins also)
              Delete old restore point(more than 3 hours)
              
              Restore in DR :
              Get the latest restorepoint
              Remove the DR DB
              Restore from Restore point snapshot.             
}

Value Proposition  :

-->This can be used Any Sql dataware house project where they want to implement BCDR with RPO less than 8 hours. 
-->This tool is configurable and can be used on subscription level to make any SQL Dw DR enablement.
