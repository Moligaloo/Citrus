# Citrus
A succinct language for relational query.

# Introduction
Citrus is a new query language that can be compiled to SQL to execute query on relational database (Currently only SQLite-compatible SQL syntax is supported). Compared to SQL, Citrus is much more succinct and intuitive (for programmers),  it borrowed many syntax from other programming languages, e.g. id selector from CSS.

# Examples

## Create a new table

`+@` means create a new table,  `+` means to create, `@` means this operator is for collection(table)
 `+@?` means to create a new table if not exist, `?` means optional.

```
+@?users(id: integer!++, name:text, gender:integer, location: text?)
```

Converted SQL
```sql
create table if not exists users(
	id integer primary key autoincrement,
	name text not null,
	gender integer not null,
	location text
);
```

## Insert new entry to table

`+` means to insert an entry to table, after which is the table name, and values are inside a pair of parenthesis (Like Objective-C's named parameters).
```
+users(name: "Moligaloo", gender: "male")
```

Converted SQL
```sql
insert into users(name, gender) values("Moligaloo", "male");
```

## Retrieve values 

### Select field(s) from a table
use `fields@table_name[where_clause]`, `@` is "at", similar meaning with "from". Conditions inside bracket style is borrowed from CSS. 

Example:
```
name@users[gender="male"]
```

Converted SQL:
```sql
select name from users where gender = "male";
```

### Select all fields from a table
Simply the table name
```
users
```
Converted SQL:
```
select * from users;
```

### Select field by id
Just use `#` operator, `#n` is equivalent to `[id=n]`, it is also borrowed from CSS.

```plain
gender@users#123
```
Converted SQL:

```sql
select gender from users where id = 123;
```

## Modify values

use `update_pairs@table_name[where_clause]`

```plain
location="Shanghai"@users#123
```
Converted SQL:
```sql
update users set location = "Shanghai" where id = 123;
```

## Delete entries 

use `-table_name[where_clause]`, `-` means delete.

```plain
-users[location = "Shanghai"]
```
Converted SQL:
```sql
delete from users where location = "Shanghai";
```

## Drop table
use `-@` operator
```
-@users
```
Converted SQL
```sql
drop table users;
```



