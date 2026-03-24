import sqlite3
import os

source_db_path = 'from_old_tracker.db'
if not os.path.exists(source_db_path):
    print(f"Error: {source_db_path} not found.")
    exit(1)

os.makedirs('assets', exist_ok=True)
dest_db_path = 'assets/health_tracker_seed.db'
if os.path.exists(dest_db_path):
    os.remove(dest_db_path)

src = sqlite3.connect(source_db_path)
dst = sqlite3.connect(dest_db_path)

# Create Flutter App Schema
dst.executescript('''
CREATE TABLE food_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    item TEXT NOT NULL,
    calories INTEGER NOT NULL,
    protein INTEGER NOT NULL,
    carbs INTEGER NOT NULL,
    fats INTEGER NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE water_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    ml INTEGER NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE medicines (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    reminder_time TEXT NOT NULL,
    type TEXT DEFAULT 'tablet',
    active INTEGER DEFAULT 1
);
CREATE TABLE medicine_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    medicine_id INTEGER NOT NULL,
    taken_at TEXT NOT NULL,
    FOREIGN KEY (medicine_id) REFERENCES medicines(id)
);
CREATE TABLE weight_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    weight_kg REAL NOT NULL
);
CREATE TABLE fasting_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    start_time TEXT NOT NULL,
    end_time TEXT,
    duration_min INTEGER
);
CREATE TABLE common_meals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    calories INTEGER NOT NULL,
    protein INTEGER NOT NULL,
    carbs INTEGER NOT NULL,
    fats INTEGER NOT NULL,
    log_count INTEGER DEFAULT 1,
    last_logged TEXT
);
CREATE TABLE personal_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_type TEXT NOT NULL,
    value REAL NOT NULL,
    achieved_date TEXT NOT NULL
);
''')

# Migrate data from old db
try:
    foods = src.execute('SELECT date, item, calories, protein, carbs, fats FROM food_logs').fetchall()
    dst.executemany('INSERT INTO food_logs (date, item, calories, protein, carbs, fats) VALUES (?,?,?,?,?,?)', foods)
    print(f"Migrated {len(foods)} food logs")
    
    # Auto-populate common_meals
    for date, item, cal, p, c, f in foods:
        existing = dst.execute('SELECT log_count FROM common_meals WHERE name = ?', (item,)).fetchone()
        if existing:
            dst.execute('UPDATE common_meals SET log_count = log_count + 1, last_logged = ? WHERE name = ?', (date, item))
        else:
            dst.execute('INSERT INTO common_meals (name, calories, protein, carbs, fats, log_count, last_logged) VALUES (?,?,?,?,?,1,?)', (item, cal, p, c, f, date))
except Exception as e:
    print("Error migrating food_logs:", e)

try:
    waters = src.execute('SELECT date, ml FROM water_logs').fetchall()
    dst.executemany('INSERT INTO water_logs (date, ml) VALUES (?,?)', waters)
    print(f"Migrated {len(waters)} water logs")
except Exception as e:
    print("Error migrating water_logs:", e)

try:
    meds = src.execute('SELECT id, name, reminder_time FROM medicines').fetchall()
    dst.executemany('INSERT INTO medicines (id, name, reminder_time, type, active) VALUES (?,?,?,"tablet",1)', meds)
    print(f"Migrated {len(meds)} medicines")
except Exception as e:
    print("Error migrating medicines:", e)

try:
    med_logs = src.execute('SELECT date, medicine_id, taken_at FROM medicine_logs').fetchall()
    dst.executemany('INSERT INTO medicine_logs (date, medicine_id, taken_at) VALUES (?,?,?)', med_logs)
    print(f"Migrated {len(med_logs)} medicine logs")
except Exception as e:
    print("Error migrating medicine_logs:", e)

try:
    weights = src.execute('SELECT date, weight_kg FROM weight_logs').fetchall()
    dst.executemany('INSERT INTO weight_logs (date, weight_kg) VALUES (?,?)', weights)
    print(f"Migrated {len(weights)} weight logs")
except Exception as e:
    print("Error migrating weight_logs:", e)

try:
    fasts = src.execute('SELECT start_time, end_time, duration_min FROM fasting_logs').fetchall()
    dst.executemany('INSERT INTO fasting_logs (start_time, end_time, duration_min) VALUES (?,?,?)', fasts)
    print(f"Migrated {len(fasts)} fasting logs")
except Exception as e:
    print("Error migrating fasting_logs:", e)

dst.execute('PRAGMA user_version = 1')
dst.commit()
src.close()
dst.close()

print("Migration to assets/health_tracker_seed.db complete!")
