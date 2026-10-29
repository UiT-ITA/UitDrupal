# W4

The base configuration for w4.

In this directory we have this structure:
```
w4
├─ base       - Common base for all overlays, this should be part of all environments
├─ production - Inherits from base, production environment base configuration
├─ test       - Inherits from base, test environments base configuration
├─ kurs       - Inherits from test, kurs environments base configuration
└─ sandbox    - Inherits from test, sandbox environments base configuration
```

Instance overlays are found in the cluster directories:
```
.
├─ bgo1-prod
│  └─ w4         - Inherits from base/w4/production
└─ bgo1-test
   ├─ w4         - Inherits from base/w4/test
   ├─ w4-kurs    - Inherits from base/w4/kurs
   └─ w4-sandbox - Inherits from base/w4/sandbox
```

See [docs/apps/w4.md](../../docs/apps/w4.md) for more information on the application.