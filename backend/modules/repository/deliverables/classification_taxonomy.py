"""Versioned project taxonomy and transparent bootstrap examples.

These authored development examples are NOT faculty-reviewed manuscripts and
must not be used to claim real-world accuracy. A reviewed dataset can replace
them through NaiveBayesClassifier.train_from_examples without changing callers.
"""

MODEL_VERSION = 'project-focus-3.1'
TRAINING_SOURCE = 'Authored development examples; not faculty-reviewed'

TRAINING_EXAMPLES = {
    'IoT': [
        'An agricultural monitoring platform collects soil moisture and environmental sensor readings. Embedded devices transmit field telemetry and irrigation alerts.',
        'A classroom climate monitor uses ESP32 microcontrollers and temperature sensors to automate ventilation through an MQTT gateway.',
        'Our connected water quality instruments measure pH and turbidity. Wireless sensor nodes send real time measurements to a dashboard.',
        'Smart city asset monitoring integrates physical sensors, connected devices and embedded controllers for remote infrastructure telemetry.',
        'An Arduino sensor device tracks greenhouse humidity and soil measurements. The system controls watering through actuators.',
    ],
    'Machine Learning': [
        'A disease prediction system trains an AI ML component on labelled patient data. The classifier predicts risk and is evaluated on an independent dataset.',
        'We train a convolutional neural network to recognize plant disease from images. TensorFlow inference supplies predictions to farmers.',
        'A learned recommendation engine uses collaborative filtering and model training to personalize product suggestions.',
        'Our predictive model learns patterns from historical data. We evaluate precision and recall before deploying neural network inference.',
        'An AI assisted triage system uses machine learning and a training dataset to produce traceable disease predictions and model performance metrics.',
    ],
    'Cybersecurity': [
        'An automated penetration testing and threat hunting platform detects vulnerabilities and produces remediation recommendations.',
        'A malware detection tool inspects suspicious executable behavior. Intrusion detection and incident response are its core functions.',
        'The proposed security gateway provides cryptographic verification and protects against brute force attacks and SQL injection.',
        'A zero trust authentication gateway enforces multi factor verification. Its central purpose is threat prevention and tamper proof auditing.',
        'Our vulnerability scanner performs authorized security testing and identifies exploitable network weaknesses for a security analyst.',
    ],
    'Data Science': [
        'Student performance analytics summarizes grade trends with statistical analysis, cohort distributions and an early warning dashboard.',
        'A sales analytics platform performs data analysis, trend exploration and business intelligence reporting from operational records.',
        'An exploratory study cleans survey data and uses statistics and visualizations to investigate factors affecting retention.',
        'Our decision support dashboard compares historical fleet logistics, route efficiency and performance indicators through data analytics.',
        'A data visualization application presents statistical distributions and descriptive insights for institutional planning.',
        'A delivery planning decision support project performs route optimization and route comparison. It evaluates feasible routes against distance, travel time and fuel-use criteria to support data-driven planning.',
        'A transport analytics project compares fleet performance indicators and trip efficiency. Route comparison and constraint-based route optimization produce planning alternatives for dispatchers.',
        'A resource planning decision support prototype analyzes operational data and compares feasible allocation scenarios. Statistical reports and optimization criteria support scheduling decisions.',
    ],
    'Web Development': [
        'A browser based campus event hub allows students to register for events. A responsive web application connects forms to a REST API.',
        'We implement a web portal using React and Node.js. The frontend provides interactive pages and the backend exposes application endpoints.',
        'An online tutoring website uses Django and HTML CSS interfaces to let users find tutors and book sessions.',
        'The proposed e commerce website supports browser shopping and checkout through a Laravel web application.',
        'Our alumni career tracker is a web based platform with an online portal and interactive browser dashboards.',
    ],
    'Mobile Development': [
        'A mobile application built in Flutter runs on Android and iOS. It provides geolocation and notifications for campus navigation.',
        'We develop a native Android app in Kotlin with touch interfaces and offline synchronization for field workers.',
        'An iOS application uses Swift and device camera capture to record inspections on a phone.',
        'A cross platform smartphone app built with React Native lets patients manage reminders and appointments.',
        'Our mobile learning app provides offline lessons and push notifications through a Dart Flutter interface.',
    ],
    'Cloud Computing': [
        'A cloud storage synchronization service provides distributed file replication, serverless workers and revision snapshots.',
        'We design a scalable cloud infrastructure on AWS using Kubernetes containers, load balancing and deployment orchestration.',
        'A multi tenant cloud platform automates resource provisioning and elastic compute allocation for institutional services.',
        'Our distributed storage system synchronizes object storage across cloud regions and monitors service availability.',
        'The project implements infrastructure orchestration and serverless processing through Azure functions and container deployment.',
    ],
    'Game Development': [
        'An educational game built in Unity implements game mechanics, interactive levels, collision physics and player progression.',
        'We develop a multiplayer game with an Unreal Engine simulation and real time player synchronization.',
        'A serious game teaches disaster preparedness through playable scenarios, characters and a scoring system.',
        'Our virtual reality game uses a game engine, animated sprites and physics driven interaction.',
        'The project designs an interactive adventure game with levels, enemies, game physics and a playable learning environment.',
    ],
    'Desktop Applications': [
        'A standalone desktop application uses a Tkinter GUI for offline inventory work on Windows computers.',
        'We implement a native desktop tool with JavaFX forms and local file processing.',
        'An Electron desktop application provides an offline graphical workspace for document annotation.',
        'Our Windows Forms program runs on laboratory PCs and offers a desktop user interface with local storage.',
        'A cross platform desktop app built in Qt provides graphical controls for scientific measurements.',
    ],
    'Database Systems': [
        'A database optimization project evaluates indexing strategies and query execution plans in PostgreSQL.',
        'We develop a database engine extension for transaction management and relational query optimization.',
        'A schema design study compares normalization and stored procedures to preserve data integrity.',
        'Our distributed database system studies replication, query planning and ACID transaction guarantees.',
        'The project focuses on database administration and performance tuning through SQL indexes and query benchmarks.',
    ],
    'Network Systems': [
        'A network monitoring platform measures bandwidth and connectivity across routers and switches.',
        'We design network topology and routing configuration for a campus LAN and WAN infrastructure.',
        'A network administration tool manages TCP IP protocols, DNS and DHCP configuration.',
        'The project evaluates packet routing, network performance and wireless connectivity in an institutional network.',
        'Our network infrastructure controller configures switching, VPN tunnels and network device management.',
    ],
    'Information Systems': [
        'A hospital billing information system manages invoices, patient charges, payment records and financial reports.',
        'An inventory management system tracks stock, purchase orders and reorder requests through structured operational workflows.',
        'A patient records information system stores clinical histories and supports authorized record retrieval and updating.',
        'The proposed appointment scheduling system manages patient bookings, availability and administrative records.',
        'A pharmacy management system maintains medicine inventory, dispensing records and prescription workflows.',
        'A laboratory information system tracks test requests, specimens and diagnostic result records.',
        'An institutional records management system organizes forms, approvals and reporting for administrative operations.',
        'A ward management system maintains admissions, bed allocation and patient discharge records.',
        'An event information system manages event publishing, attendee registration, attendance tracking and organizer records. Staff retrieve event records and participation reports from a centralized directory.',
        'A clinical intake information system records vital signs and presenting complaints. Configurable priority categories organize the triage queue, triage history and patient handoff records without a learned predictive model.',
        'A hospital occupancy information system maintains bed availability, patient assignments and patient transfers. Admission and discharge updates keep ward records and occupancy reports consistent.',
        'A municipal service information system stores application records, permit requests, processing queues and approval histories. Clerks coordinate structured records and operational workflows.',
        'A hotel operations information system maintains room availability, guest assignments, booking records and check-in updates. Occupancy dashboards support reception staff.',
        'A school activities records management service maintains event schedules, attendance records and registration records. Organizers coordinate event management and participation reporting.',
        'A graduate information system maintains alumni profiles, employment records and career histories. A searchable directory supports authorized alumni affairs staff with profile management, announcements and institutional records.',
        'An institutional alumni information service tracks graduate employment, career milestones, skills and achievements. Profile management and a searchable directory support networking and administrative reporting.',
    ],
}

# Explicit evidence guards: ordinary authentication, SQL storage and deployment
# do not establish security/database/cloud as the project's primary purpose.
FOCUS_SIGNALS = {
    'IoT': ['iot', 'internet of things', 'sensor', 'sensors', 'soil moisture', 'soil-moisture', 'embedded', 'microcontroller', 'arduino', 'esp32', 'mqtt', 'actuator', 'telemetry', 'connected devices', 'sensor-integrated'],
    'Machine Learning': ['machine learning', 'ai/ml', 'ai-assisted', 'ai assisted', 'ai-powered', 'ai powered', 'neural network', 'deep learning', 'model training', 'training dataset', 'approved dataset', 'tensorflow', 'pytorch', 'learned model', 'disease predictions', 'disease prediction', 'model performance'],
    'Cybersecurity': ['penetration testing', 'threat hunting', 'threat hunter', 'vulnerability', 'vulnerabilities', 'vulnerability scanner', 'intrusion detection', 'malware', 'cryptographic', 'cryptography', 'zero trust', 'zero-trust', 'brute force', 'security testing', 'threat detection'],
    'Data Science': ['analytics', 'statistical analysis', 'statistics', 'data analysis', 'data visualization', 'business intelligence', 'exploratory', 'grade trends', 'cohort distributions', 'performance indicators', 'early warning', 'trend exploration', 'route optimization', 'route comparison', 'compare feasible routes', 'data-driven planning'],
    'Web Development': ['web application', 'web portal', 'web platform', 'web-based', 'browser based', 'browser-based', 'website', 'online portal', 'responsive web', 'frontend', 'react', 'django', 'laravel', 'node.js', 'nodejs'],
    'Mobile Development': ['mobile app', 'mobile application', 'smartphone', 'android', 'ios', 'flutter', 'kotlin', 'react native', 'swift', 'phone app'],
    'Cloud Computing': ['cloud storage', 'distributed storage', 'cloud infrastructure', 'cloud synchronization', 'serverless', 'resource provisioning', 'elastic compute', 'kubernetes', 'distributed file', 'storage synchronization', 'infrastructure orchestration'],
    'Game Development': ['game', 'game engine', 'game mechanics', 'unity', 'unreal', 'playable', 'player progression', 'multiplayer', 'game physics'],
    'Desktop Applications': ['desktop application', 'desktop app', 'standalone desktop', 'tkinter', 'javafx', 'windows forms', 'electron', 'qt', 'desktop tool'],
    'Database Systems': ['query optimization', 'query execution', 'database engine', 'database optimization', 'database administration', 'normalization', 'query planning', 'performance tuning', 'database replication'],
    'Network Systems': ['network topology', 'routing', 'switching', 'network monitoring', 'network infrastructure', 'network administration', 'bandwidth', 'routers', 'dhcp', 'tcp ip'],
    'Information Systems': ['information system', 'records management', 'inventory management', 'billing', 'patient records', 'appointment', 'appointments', 'pharmacy', 'laboratory', 'ward management', 'invoices', 'purchase orders', 'stock', 'booking', 'bookings', 'prescription', 'specimens', 'bed allocation', 'administrative workflows', 'event management', 'event records', 'attendance tracking', 'attendance records', 'registration records', 'patient intake', 'triage queue', 'triage history', 'patient handoff', 'bed availability', 'bed records', 'patient assignment', 'patient assignments', 'patient transfers', 'occupancy reports', 'alumni information', 'profile management', 'employment records', 'career history', 'searchable directory'],
}

DOMAIN_SIGNALS = {
    'Agriculture & Environment': ['agriculture', 'agricultural', 'farm', 'farmers', 'crop', 'crops', 'soil', 'irrigation', 'greenhouse', 'pollution', 'environmental monitoring'],
    'Healthcare': ['patient', 'patients', 'clinical', 'hospital', 'disease', 'triage', 'pharmacy', 'medicine', 'prescription', 'healthcare', 'vital signs', 'specimens', 'ward'],
    'Education': ['student', 'students', 'campus', 'academic', 'learning', 'tutoring', 'alumni', 'classroom', 'school', 'university', 'grade'],
    'Business & Commerce': ['sales', 'billing', 'inventory', 'retail', 'e commerce', 'e-commerce', 'purchase orders', 'checkout', 'business', 'customer'],
    'Transport & Logistics': ['fleet', 'logistics', 'route', 'routes', 'transport', 'traffic', 'delivery', 'vehicles'],
    'Public Services & Safety': ['smart city', 'municipal', 'disaster', 'public safety', 'infrastructure assets', 'emergency', 'hazard'],
    'Security & IT Operations': ['penetration testing', 'threat hunting', 'threat hunter', 'vulnerability', 'malware', 'network administration', 'incident response', 'cloud infrastructure'],
    'Entertainment': ['game', 'gaming', 'entertainment', 'multiplayer', 'player'],
}

TECHNOLOGY_SIGNALS = {
    'Flutter': ['flutter', 'dart'], 'React': ['react', 'react.js'],
    'Django': ['django'], 'Laravel': ['laravel'], 'Node.js': ['node.js', 'nodejs'],
    'Python': ['python'], 'Java': ['java', 'spring boot'], 'C# / .NET': ['c#', '.net', 'asp.net'],
    'PostgreSQL': ['postgresql', 'postgres'], 'MySQL': ['mysql'], 'MongoDB': ['mongodb'],
    'TensorFlow': ['tensorflow'], 'PyTorch': ['pytorch'], 'Arduino': ['arduino'],
    'ESP32': ['esp32'], 'Raspberry Pi': ['raspberry pi'], 'MQTT': ['mqtt'],
    'AWS': ['aws', 'amazon web services'], 'Azure': ['azure'], 'Docker': ['docker'],
    'Kubernetes': ['kubernetes'], 'Unity': ['unity'], 'Unreal Engine': ['unreal engine'],
    'Android': ['android'], 'iOS': ['ios'], 'Kotlin': ['kotlin'], 'Swift': ['swift'],
}
