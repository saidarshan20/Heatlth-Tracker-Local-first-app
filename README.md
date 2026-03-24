# Personal Health Tracker

A personal health tracking Flutter application designed to help you stay on top of your daily wellness goals. The application enables tracking of calories, macros, water intake, and medicines. 

## Features

- **Daily Intake Logging:** Easily log calories and macromolecules.
- **Water & Medicine Tracking:** Set up reminders and track your daily hydration and medication needs.
- **Smart Insights:** Integrated with Google Generative AI to provide smart insights and recommendations natively.
- **Robust Notifications:** Uses local notifications and timezone awareness to schedule and deliver reminders effectively without missing them.
- **Offline First:** Built on local SQLite database (using `sqflite`), meaning your data stays strictly on your device and the app doesn't require constant internet connectivity.
- **Data Visualization:** Built-in charts and graphs using `fl_chart` to visualize your health data over time.

## Tech Stack

- **Framework:** Flutter (Dart)
- **State Management:** Provider
- **Local Database:** sqflite (and sqflite_common_ffi for desktop)
- **AI Integration:** google_generative_ai
- **Charting:** fl_chart
- **Notifications:** flutter_local_notifications, flutter_timezone

## Getting Started

### Prerequisites
- Flutter SDK (`^3.11.1`)
- Android Studio / Xcode (for emulation/compilation)

### Setup
1. Clone the repository to your local machine.
2. In the project root, run `flutter pub get` to install all dependencies.
3. Add a `.env` file in the root directory and ensure you configure your API keys (e.g., Gemini AI API keys).
4. Run `flutter build` or `flutter run` to test the application in an emulator or connected device.

### Migration Scripts 
If you are coming from the older version of the tracker:
- A python script (`scripts/migrate_db.py`) and a legacy SQLite dump (`scripts/from_old_tracker.db`) are available to help you transfer your previous data. Run the python script to parse and export it to the new flutter app schema.
