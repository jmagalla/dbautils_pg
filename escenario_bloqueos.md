# Escenario Controlado de Bloqueos en PostgreSQL
**Guía para ejecutar pruebas de bloqueos en dos terminales separadas.**

Este documento indica exactamente qué comandos deberá ejecutar un tercero en dos sesiones independientes de `psql`.

---

# 1. Preparación inicial
Ejecutar una sola vez (en cualquier terminal):

```sql
CREATE TABLE demo_lock (
    id SERIAL PRIMARY KEY,
    valor TEXT
);

INSERT INTO demo_lock (valor)
SELECT 'fila ' || g
FROM generate_series(1,10) g;
```

---

# 2. Escenario 1 — Bloqueo por UPDATE sin commit

##  Terminal 1 (Sesión A)
```sql
BEGIN;
UPDATE demo_lock
SET valor = 'A-bloqueando'
WHERE id = 1;
```

*(No ejecutar COMMIT)*

## Terminal 2 (Sesión B)
```sql
UPDATE demo_lock
SET valor = 'B-bloqueado'
WHERE id = 1;
```

Esta sesión quedará bloqueada.

---

# 3. Escenario 2 — Lock por ALTER TABLE

##  Terminal 1 (Sesión A)
```sql
BEGIN;
ALTER TABLE demo_lock ADD COLUMN nuevo TEXT;
```

##  Terminal 2 (Sesión B)
```sql
SELECT * FROM demo_lock;
```

---

# 4. Escenario 3 — Deadlock controlado

##  Terminal 1 (Sesión A)
```sql
BEGIN;
UPDATE demo_lock SET valor='A1' WHERE id=1;
```

##  Terminal 2 (Sesión B)
```sql
BEGIN;
UPDATE demo_lock SET valor='B1' WHERE id=2;
```

Ahora el cruce:

###  Terminal 1
```sql
UPDATE demo_lock SET valor='A2' WHERE id=2;
```

###  Terminal 2
```sql
UPDATE demo_lock SET valor='B2' WHERE id=1;
```

La terminal 2 mostrará:
```
ERROR: deadlock detected
```

---

# 5. Escenario 4 — Lock por SELECT FOR UPDATE

##  Terminal 1 (Sesión A)
```sql
BEGIN;
SELECT * FROM demo_lock WHERE id = 1 FOR UPDATE;
```

##  Terminal 2 (Sesión B)
```sql
UPDATE demo_lock SET valor = 'espera' WHERE id = 1;
```

---

# 6. Escenario 5 — Lock prolongado (idle in transaction)

##  Terminal 1 (Sesión A)
```sql
BEGIN;
SELECT 1;
```

*(No cerrar la transacción)*

##  Terminal 2 (Sesión B)
```sql
UPDATE demo_lock SET valor = 'bloqueado' WHERE id = 3;
```

---
