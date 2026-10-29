# Multi-region disaster recovery of persistent data

These scenarios are mostly relevant in cases of an entire region going down.
Kubernetes has automatic failover in case a singular node goes down. We are
considering if e.g there is a huge fire or something similar causing the entire
bgo1 region to be down and we are required to make an application available in a
different region.

> **This is not a guide, it's a reference!** You need to consider your
> application when designing how to do the disaster recovery. This is mostly to
> highlight some solutions we have tried and document them so it is easier for
> the next person that require high availability. High availability comes with
> extra complexity, so the first question would be whether you need the
> application even needs to be easily switched multi-regionally!

> **This is not automatic currently!** These scenarios do not handle automatic
> switch-over and still require manual work to do so. This means it does not
> satisfy a requirement of automatic multi-region failover. As of writing, this
> is not feasibly possible in RAIL, but there are discussions on how this could
> be solved.

**Table of contents**

- [Multi-region disaster recovery of persistent data](#multi-region-disaster-recovery-of-persistent-data)
  - [1. Restore on disaster](#1-restore-on-disaster)
    - [Pros \& Cons](#pros--cons)
    - [Example of disaster recovery procedure](#example-of-disaster-recovery-procedure)
    - [How to implement for postgres](#how-to-implement-for-postgres)
    - [How to implement for a pvc](#how-to-implement-for-a-pvc)
  - [2. Replicated environment](#2-replicated-environment)
    - [Pros \& Cons](#pros--cons-1)
    - [Example of disaster recovery procedure](#example-of-disaster-recovery-procedure-1)
      - [Detaching the replica (Failover)](#detaching-the-replica-failover)
      - [Promoting the cluster (Graceful)](#promoting-the-cluster-graceful)
    - [How to implement for postgres](#how-to-implement-for-postgres-1)
    - [How to implement for pvc](#how-to-implement-for-pvc)

## 1. Restore on disaster

In this scenario we place ourself in a reactive position where we optimize for
getting an environment up and running from a backup quickly.

### Pros & Cons

Pros:

- Low complexity, it is relatively easy to set up and to perform, low need for
  maintenance

Cons:

- We need to be 100% sure we have control of where the backup data is as the
  entire region might be gone.
- Needs to be tested that it works properly relatively often to ensure it works
  in disaster scenario
- Might take a while to restore if large database / data set
- Can be hard to properly test as you optimally would make the entire region
  unavailable to the disaster region to make 100% sure that you can recover from
  that scenario.

### Example of disaster recovery procedure

> **NB:** You should document exact steps for your application, this serves as
> an example of how the steps generally look.

1. Uncomment the manifest in disaster environment. e.g
   `/osl1-prod/RAIL/{app}.yaml`
2. Update recovery target times. e.g `recovery_target` post build var
3. Commit and push
4. Wait for environment to be up and ready
5. Switch relevant external ingresses

Given that everything is set up similarly to later sections, the application
should automatically be sourcing from an available S3 bucket.

### How to implement for postgres

Create a patch on your postgres and patch it to bootstrap from recovery.

> **NB:** If you automatically have backup to S3, make sure that the S3 in the
> **disaster bucket** is cleaned up, otherwise creating the recovery cluster
> will fail due to existing backup existing. You should make sure to put this
> into your cleanup routine!

**Example of postgres patch for bootstrapping from recovery:**

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${app_name}-db
spec:
  bootstrap:
    initdb:
    recovery:
      source: source
      recoveryTarget:
        # Example time target for the recovery
        # Optimally make this a post build variable and use one timestamp everywhere
        targetTime: "2026-02-12 01:00:00.00000+01"
  externalClusters:
    - name: source
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: bgo1-objectstore
          serverName: ${db_name}

```

### How to implement for a pvc

> TODO: Currently we put it in a tar file for profile, but that is not a
> scalable way. This should be written after we land how to do s3 sync for
> directories as that will change how we do this optimally. Tl;dr will likely
> be, run a job on deployment that will do an s3 sync of a directory.


## 2. Replicated environment

In this scenario we place ourself in a proactive position where we optimize for
making sure that another environment is always available and ready to be
switched over to.

### Pros & Cons

Pros:

- Reduced risk of forgotten data, since the environment should always be up to
  date
- Low to no failover time as the environment should be replicated

Cons:

- High complexity, setting up and maintaining requires knowledge on cnpg
- Wasted compute, another environment is always running without being used
- Extra maintenance, it is another environment to check up on and ensure is
  running as expected
- Read-only, since it is replicated, we optimally shouldn't change the
  environment until we switch, requiring writing applications to be disabled
  until switchover.
- Very manual switchover

### Example of disaster recovery procedure

> **NB:** You should document exact steps for your application, this serves as
> an example of how the steps generally look.

There are two ways of doing this for the postgres part, one graceful that guarantees
that the entire data of the database is moved. This is preferred, but probably
not possible in a disaster scenario.

#### Detaching the replica (Failover)

Detaching the database will cause it to work as a standalone replica, in order
to put it back in sync with the distributed cluster you will need to delete the
broken primary and set it up as a replica to the standalone.

**Steps:**

1. Change `.spec.replica.primary` to be the replica that should now be primary.
2. Commit, push, reconcile
3. The replica should now act as a primary

#### Promoting the cluster (Graceful)

A promotion of a cluster happens in two steps, the demotion of the existing
primary and then the promotion of the new primary. In this time period, both
clusters will be in a read-only state, which means no writing will be possible
to the clusters. If your application requires write possibility, then it is
basically down in this time period.

**Demoting:**

1. In the primary cluster manifest, change the `.spec.replica.primary` to be the
   replica cluster. (DO NOT CHANGE THE REPLICA!)
2. Commit, push and reconcile
3. Describe the production cluster, it should have a demotionToken. Copy this
   and go to promoting

**Example of how the primary to be demoted manifest should look:**

```yaml
# bgo1
replica:
  primary: ${app_name}-osl1-prod
  source: ${app_name}-bgo1-prod
```

**Promoting:**

1. In the replica cluster manifest
2. Change `.spec.replica.primary` to be the replica that will be promoted
3. Change `.spec.replica.promotionToken` to be the demotionToken you get in the
   demoting step.
4. Commit, push and reconcile
5. At this point, the database should replay the last of the wal files and take
   over as the primary

> **NB:** It is crucial that both of the properties must be reconciled at the
> same time! if the promotionToken is omitted, a failover will be triggered
> causing the clusters to go out of sync and this not being graceful!


**Example of how the replica to be promoted manifest should look:**

```yaml
# osl1
replica:
  primary: ${app_name}-osl1-prod
  promotionToken: <PROMOTION_TOKEN>
  source: ${app_name}-bgo1-prod
```

### How to implement for postgres

We do recommend reading the cnpg section about [replica
clusters](https://cloudnative-pg.io/docs/1.28/replica_cluster/).

There are two ways of doing replication with postgres and cnpg, WAL shipping and
streaming replication. We only detail WAL shipping in this case as streaming
replication requires a direct connection between the database clusters, which is
difficult when running in two regions.

WAL shipping allows two clusters to stay in sync through the primary cluster
writing it's WAL to S3 and then the replicas can read it to stay in synch within
about ~5 minutes. This allows us to keep two clusters in different regions
somewhat in sync without a direct connection.

1. Set up [S3 backup with WAL](https://rail.uib.no/docs/database.html#backup) on
   at least the primary replica and object stores on both regions.
2. Take down the disaster recovery environment. We need to bootstrap it from
   recovery, which requires it not existing. NB: Remember to remove S3 backup on
   the disaster recovery if it exists, otherwise the cluster will fail to come
   back up.
3. Patch the replica cluster similarly to the example below.
4. Once the replica cluster is up, it should start to restore from the source
   cluster

**Example of cluster patch that assumes bgo1 is primary and osl1 is replica:**

```yaml
# bgo1 - primary
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${app_name}-db
spec:
  # No boostrap override as we want this to bootstrap as an empty cluster
  replica:
    self: ${app_name}-bgo1-prod
    primary: ${app_name}-bgo1-prod # This should refer to the primary cluster
    source: ${app_name}-bgo1-prod # This should refer to the sourced cluster (usually primary)
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: ${app_name}-bgo1-prod-db-store
  externalClusters:
    - name: ${app_name}-bgo1-prod
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: ${app_name}-bgo1-prod-db-store
          serverName: ${app_name}-db
    - name: ${app_name}-osl1-prod
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: ${app_name}-osl1-prod-db-store
          serverName: ${app_name}-db

```

```yaml
# osl1 - replica
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${app_name}-db
spec:
  bootstrap:
    initdb: # Disables the default empty init
    recovery:
      source: ${app_name}-bgo1-prod # This should refer to the sourced cluster (usually primary)
      database: ${app_name}
      owner: ${app_name}
      secret:
        name: ${app_name}-db-secret
  replica:
    self: ${app_name}-osl1-prod
    primary: ${app_name}-bgo1-prod # This should refer to the primary cluster
    source: ${app_name}-bgo1-prod # This should refer to the sourced cluster (usually primary)
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: ${app_name}-osl1-prod-db-store
  externalClusters:
    - name: ${app_name}-bgo1-prod
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: ${app_name}-bgo1-prod-db-store
          serverName: ${app_name}-db
    - name: ${app_name}-osl1-prod
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: ${app_name}-osl1-prod-db-store
          serverName: ${app_name}-db

```

### How to implement for pvc

> TODO: Currently we put it in a tar file for profile, but that is not a
> scalable way. This should be written after we land how to do s3 sync for
> directories as that will change how we do this optimally. Tl;dr will likely
> be, run a cronjob that continuously syncs from S3 until it detaches, then the
> cron job is deleted
