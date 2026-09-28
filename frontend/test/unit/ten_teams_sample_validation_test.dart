import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/user_management/bulk_import/official_class_list_parser.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';

void main() {
  group('16 Teams 4th Year - 4A Different Systems & 4B One System', () {
    test('validates student by year level CSV parsing (64 students)', () {
      const studentCsv = '''LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
,Program,Registered,Officially Enrolled,,,,,,,,
,Bachelor of Science in Information Technology,64,64,,,,,,,,
,TOTAL,,,,,,,,,,
,,64,64,,,,,,,,
LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
Bachelor of Science in Information Technology,,,,,,,,,,,
,#,Student No,Name,Program,Major,Level,,Gender,Status,Date,Date
,1,4001,"VILLAR, Marcus",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,2,4002,"ONG, Patricia",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,3,4003,"SALAZAR, Ethan",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,4,4004,"CASTILLO, Zoe",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,5,4005,"TORRES, Ryan",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,6,4006,"VILLANUEVA, Nina",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,7,4007,"GARCIA, Diego",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,8,4008,"RAMOS, Patricia",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,9,4009,"BAUTISTA, Carlos",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,10,4010,"SANTOS, Sophia",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,11,4011,"CRUZ, Miguel",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,12,4012,"ALCANTARA, Isabella",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,13,4013,"AQUINO, David",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,14,4014,"OCAMPO, Sarah",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,15,4015,"RIVERA, Daniel",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,16,4016,"MORALES, Jasmine",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,17,4017,"MENDOZA, Gabriel",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,18,4018,"CASTRO, Bea",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,19,4019,"LIM, Christian",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,20,4020,"NAVARRO, Joshua",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,21,4021,"VALDEZ, Adrian",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,22,4022,"YAP, Stephanie",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,23,4023,"DE LEON, Jerome",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,24,4024,"ROXAS, Camille",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,25,4025,"RAMOS, Carlo",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,26,4026,"BAUTISTA, Nicole",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,27,4027,"MENDOZA, John",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,28,4028,"CRUZ, Patricia",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,29,4029,"TORRES, Miguel",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,30,4030,"FLORES, Angela",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,31,4031,"DIZON, Francis",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,32,4032,"SALAZAR, Rhea",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,Print Info:,,,Page 2 of,,,,,,2,
,Monday 22 June 2026,,,,,,,,,,
LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
Bachelor of Science in Information Technology,,,,,,,,,,,
,#,Student No,Name,Program,Major,Level,,Gender,Status,Date,Date
,33,4033,"HERNANDEZ, Lucas",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,34,4034,"BERNARDO, Camille",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,35,4035,"GUTIERREZ, Danilo",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,36,4036,"SALAZAR, Andrea",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,37,4037,"MORALES, Enzo",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,38,4038,"CRUZ, Valerie",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,39,4039,"MERCADO, Paolo",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,40,4040,"REYES, Bianca",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,41,4041,"DIAZ, Giancarlo",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,42,4042,"SANTOS, Rachelle",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,43,4043,"DELA CRUZ, Marco",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,44,4044,"FLORES, Hannah",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,45,4045,"GARCIA, Leandro",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,46,4046,"GOMEZ, Kirsten",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,47,4047,"PINEDA, Jerome",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,48,4048,"CASTRO, Monica",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,49,4049,"AGUILAR, Timothy",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,50,4050,"DOMINGO, Clarisse",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,51,4051,"PASCUAL, Nathaniel",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,52,4052,"SORIANO, Fiona",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,53,4053,"TAN, Oliver",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,54,4054,"TOLENTINO, Kaye",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,55,4055,"MIRANDA, Derrick",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,56,4056,"FERNANDEZ, Althea",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,57,4057,"VALENZUELA, Justin",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,58,4058,"ROMERO, Alyssa",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,59,4059,"MARQUEZ, Vincent",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,60,4060,"SOTTO, Danica",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,61,4061,"TAN, Gabriel",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,62,4062,"SORIANO, Chloe",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,63,4063,"MERCADO, Pauline",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,64,4064,"PASCUAL, Rafael",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,TOTAL,,,,64,64,,,,,,
''';

      final result = parseOfficialClassListCsv(studentCsv);
      expect(result.students.length, 64);
      expect(result.metadata['school_year'], '2026-2027');
      expect(result.metadata['semester'], '1st Semester');
      expect(result.metadata['year_level'], '4th Year');
    });

    test('validates Section 4A Different Systems CSV (8 teams, 2 advisers with 4 teams each)', () {
      const sec4ACsv = '''Section,BSIT-4A

ADVISER: Ricardo Fontanilla
Team Name,Names,Project / Module
Team SkyLedger,Marcus Villar,Alumni Career Tracker and Graduate Employability Analytics
,Patricia Ong,
,Ethan Salazar,
,Zoe Castillo,
Team BioPulse,Ryan Torres,AI-Powered Patient Vital Triage and Telemedicine Monitoring System
,Nina Villanueva,
,Diego Garcia,
,Patricia Ramos,
Team SafeCity,Carlos Bautista,Smart Campus IoT Infrastructure and Emergency Hazard Sentinel
,Sophia Santos,
,Miguel Cruz,
,Isabella Alcantara,
Team CyberShield,David Aquino,Zero-Trust Campus Network Security and Threat Intelligence Gateway
,Sarah Ocampo,
,Daniel Rivera,
,Jasmine Morales,

ADVISER: Jonathan Beltran
Team Name,Names,Project / Module
Team AgriSense,Gabriel Mendoza,Automated Hydroponics Farming and Microclimate Control Portal
,Bea Castro,
,Christian Lim,
,Joshua Navarro,
Team AquaFlow,Adrian Valdez,Municipal Smart Water Distribution and Leak Detection Network
,Stephanie Yap,
,Jerome De Leon,
,Camille Roxas,
Team Solarix,Carlo Ramos,Distributed Solar Energy Harvesting and Microgrid Inverter Controller
,Nicole Bautista,
,John Mendoza,
,Patricia Cruz,
Team TerraForge,Miguel Torres,Precision Agriculture Soil Sensing and Autonomous Fertilizer Dispenser
,Angela Flores,
,Francis Dizon,
,Rhea Salazar,
''';

      final result = parseTeamBulkCsv(sec4ACsv);
      expect(result.rows.length, 8);
      expect(result.section, 'BSIT-4A');
      expect(result.systemName, isNull);

      final advFontanilla = result.rows.where((r) => r['adviser_name'] == 'Ricardo Fontanilla').toList();
      final advBeltran = result.rows.where((r) => r['adviser_name'] == 'Jonathan Beltran').toList();
      expect(advFontanilla.length, 4);
      expect(advBeltran.length, 4);

      for (final team in result.rows) {
        expect(team['member_ids'], hasLength(4));
        expect(team['section'], 'BSIT-4A');
      }
    });

    test('validates Section 4B One System CSV (8 teams, 2 advisers with 4 teams each under shared system)', () {
      const sec4BCsv = '''System Name,Smart University Enterprise Operations & Resource Ecosystem
Project Manager,Lucas Hernandez
Section,BSIT-4B

ADVISER: Analiza Corpuz
Team Name,Names,Project / Module
Team NovaLearn,Lucas Hernandez,Adaptive LMS & Automated Assessment Engine Module
,Camille Bernardo,
,Danilo Gutierrez,
,Andrea Salazar,
Team LogiChain,Enzo Morales,Central Storage & Smart Inventory Dispatch Module
,Valerie Cruz,
,Paolo Mercado,
,Bianca Reyes,
Team EnerGrid,Giancarlo Diaz,Campus Power Consumption & Smart Grid Analytics Module
,Rachelle Santos,
,Marco Dela Cruz,
,Hannah Flores,
Team OmniPort,Leandro Garcia,Automated University Procurement & Vendor Quotation Module
,Kirsten Gomez,
,Jerome Pineda,
,Monica Castro,

ADVISER: Renato Villanueva
Team Name,Names,Project / Module
Team MediTrack,Timothy Aguilar,Pharmacy Dispensing & Clinic Appointment Module
,Clarisse Domingo,
,Nathaniel Pascual,
,Fiona Soriano,
Team EcoRoute,Oliver Tan,Electric Shuttle Fleet & Route Optimization Module
,Kaye Tolentino,
,Derrick Miranda,
,Althea Fernandez,
Team BuildSense,Justin Valenzuela,Facility Maintenance Ticketing & Preventive Inspection Module
,Alyssa Romero,
,Vincent Marquez,
,Danica Sotto,
Team DataPulse,Gabriel Tan,Institutional Research & Predictive Student Success Module
,Chloe Soriano,
,Pauline Mercado,
,Rafael Pascual,
''';

      final result = parseTeamBulkCsv(sec4BCsv);
      expect(result.rows.length, 8);
      expect(result.section, 'BSIT-4B');
      expect(result.systemName, 'Smart University Enterprise Operations & Resource Ecosystem');
      expect(result.projectManager, 'Lucas Hernandez');

      final advCorpuz = result.rows.where((r) => r['adviser_name'] == 'Analiza Corpuz').toList();
      final advVillanueva = result.rows.where((r) => r['adviser_name'] == 'Renato Villanueva').toList();
      expect(advCorpuz.length, 4);
      expect(advVillanueva.length, 4);

      for (final team in result.rows) {
        expect(team['member_ids'], hasLength(4));
        expect(team['section'], 'BSIT-4B');
        expect(team['system_name'], 'Smart University Enterprise Operations & Resource Ecosystem');
      }
    });

    test('validates combined team roster CSV (4A different systems + 4B one system)', () {
      const combinedCsv = '''Section,BSIT-4A
ADVISER: Ricardo Fontanilla
Team Name,Names,Project / Module
Team SkyLedger,Marcus Villar,Alumni Career Tracker and Graduate Employability Analytics
,Patricia Ong,
,Ethan Salazar,
,Zoe Castillo,
Team BioPulse,Ryan Torres,AI-Powered Patient Vital Triage and Telemedicine Monitoring System
,Nina Villanueva,
,Diego Garcia,
,Patricia Ramos,
Team SafeCity,Carlos Bautista,Smart Campus IoT Infrastructure and Emergency Hazard Sentinel
,Sophia Santos,
,Miguel Cruz,
,Isabella Alcantara,
Team CyberShield,David Aquino,Zero-Trust Campus Network Security and Threat Intelligence Gateway
,Sarah Ocampo,
,Daniel Rivera,
,Jasmine Morales,

ADVISER: Jonathan Beltran
Team Name,Names,Project / Module
Team AgriSense,Gabriel Mendoza,Automated Hydroponics Farming and Microclimate Control Portal
,Bea Castro,
,Christian Lim,
,Joshua Navarro,
Team AquaFlow,Adrian Valdez,Municipal Smart Water Distribution and Leak Detection Network
,Stephanie Yap,
,Jerome De Leon,
,Camille Roxas,
Team Solarix,Carlo Ramos,Distributed Solar Energy Harvesting and Microgrid Inverter Controller
,Nicole Bautista,
,John Mendoza,
,Patricia Cruz,
Team TerraForge,Miguel Torres,Precision Agriculture Soil Sensing and Autonomous Fertilizer Dispenser
,Angela Flores,
,Francis Dizon,
,Rhea Salazar,

Section,BSIT-4B
System Name,Smart University Enterprise Operations & Resource Ecosystem
Project Manager,Lucas Hernandez
ADVISER: Analiza Corpuz
Team Name,Names,Project / Module
Team NovaLearn,Lucas Hernandez,Adaptive LMS & Automated Assessment Engine Module
,Camille Bernardo,
,Danilo Gutierrez,
,Andrea Salazar,
Team LogiChain,Enzo Morales,Central Storage & Smart Inventory Dispatch Module
,Valerie Cruz,
,Paolo Mercado,
,Bianca Reyes,
Team EnerGrid,Giancarlo Diaz,Campus Power Consumption & Smart Grid Analytics Module
,Rachelle Santos,
,Marco Dela Cruz,
,Hannah Flores,
Team OmniPort,Leandro Garcia,Automated University Procurement & Vendor Quotation Module
,Kirsten Gomez,
,Jerome Pineda,
,Monica Castro,

ADVISER: Renato Villanueva
Team Name,Names,Project / Module
Team MediTrack,Timothy Aguilar,Pharmacy Dispensing & Clinic Appointment Module
,Clarisse Domingo,
,Nathaniel Pascual,
,Fiona Soriano,
Team EcoRoute,Oliver Tan,Electric Shuttle Fleet & Route Optimization Module
,Kaye Tolentino,
,Derrick Miranda,
,Althea Fernandez,
Team BuildSense,Justin Valenzuela,Facility Maintenance Ticketing & Preventive Inspection Module
,Alyssa Romero,
,Vincent Marquez,
,Danica Sotto,
Team DataPulse,Gabriel Tan,Institutional Research & Predictive Student Success Module
,Chloe Soriano,
,Pauline Mercado,
,Rafael Pascual,
''';

      final result = parseTeamBulkCsv(combinedCsv);
      expect(result.rows.length, 16);

      final sec4A = result.rows.where((r) => r['section'] == 'BSIT-4A').toList();
      final sec4B = result.rows.where((r) => r['section'] == 'BSIT-4B').toList();
      expect(sec4A.length, 8);
      expect(sec4B.length, 8);

      // Section 4A teams do NOT have system_name (independent projects)
      for (final t in sec4A) {
        expect(t.containsKey('system_name'), isFalse);
      }

      // Section 4B teams DO have system_name (one shared system)
      for (final t in sec4B) {
        expect(t['system_name'], 'Smart University Enterprise Operations & Resource Ecosystem');
      }
    });

    test('validates defense schedule import CSV parsing (16 teams, 16 slots)', () {
      const scheduleCsv = '''Concept Proposal,,,,,,,,,
October 20, 2026,,,,,,,,,
Room 301,,,,,,,,,
Time,Team Name,Capstone Project,Adviser,Team Members,Chair,Panel Member 1,Panel Member 2,Panel Member 3,Documenter
8:00AM-8:30AM,Team SkyLedger,Alumni Career Tracker and Graduate Employability Analytics,Ricardo Fontanilla,Marcus Villar,Maricel Suarez,Jonathan Beltran,Analiza Corpuz,Renato Villanueva,Cecilia Magbanua
,,,,Patricia Ong,,,,,
,,,,Ethan Salazar,,,,,
,,,,Zoe Castillo,,,,,
8:30AM-9:00AM,Team BioPulse,AI-Powered Patient Vital Triage and Telemedicine Monitoring System,Ricardo Fontanilla,Ryan Torres,Maricel Suarez,Jonathan Beltran,Analiza Corpuz,Renato Villanueva,Cecilia Magbanua
,,,,Nina Villanueva,,,,,
,,,,Diego Garcia,,,,,
,,,,Patricia Ramos,,,,,
9:00AM-9:30AM,Team SafeCity,Smart Campus IoT Infrastructure and Emergency Hazard Sentinel,Ricardo Fontanilla,Carlos Bautista,Maricel Suarez,Jonathan Beltran,Analiza Corpuz,Renato Villanueva,Cecilia Magbanua
,,,,Sophia Santos,,,,,
,,,,Miguel Cruz,,,,,
,,,,Isabella Alcantara,,,,,
9:30AM-10:00AM,Team CyberShield,Zero-Trust Campus Network Security and Threat Intelligence Gateway,Ricardo Fontanilla,David Aquino,Maricel Suarez,Jonathan Beltran,Analiza Corpuz,Renato Villanueva,Cecilia Magbanua
,,,,Sarah Ocampo,,,,,
,,,,Daniel Rivera,,,,,
,,,,Jasmine Morales,,,,,
10:00AM-10:30AM,Team AgriSense,Automated Hydroponics Farming and Microclimate Control Portal,Jonathan Beltran,Gabriel Mendoza,Maricel Suarez,Ricardo Fontanilla,Analiza Corpuz,Renato Villanueva,Cecilia Magbanua
,,,,Bea Castro,,,,,
,,,,Christian Lim,,,,,
,,,,Joshua Navarro,,,,,
10:30AM-11:00AM,Team AquaFlow,Municipal Smart Water Distribution and Leak Detection Network,Jonathan Beltran,Adrian Valdez,Maricel Suarez,Ricardo Fontanilla,Analiza Corpuz,Renato Villanueva,Cecilia Magbanua
,,,,Stephanie Yap,,,,,
,,,,Jerome De Leon,,,,,
,,,,Camille Roxas,,,,,
11:00AM-11:30AM,Team Solarix,Distributed Solar Energy Harvesting and Microgrid Inverter Controller,Jonathan Beltran,Carlo Ramos,Maricel Suarez,Ricardo Fontanilla,Analiza Corpuz,Renato Villanueva,Cecilia Magbanua
,,,,Nicole Bautista,,,,,
,,,,John Mendoza,,,,,
,,,,Patricia Cruz,,,,,
11:30AM-12:00PM,Team TerraForge,Precision Agriculture Soil Sensing and Autonomous Fertilizer Dispenser,Jonathan Beltran,Miguel Torres,Maricel Suarez,Ricardo Fontanilla,Analiza Corpuz,Renato Villanueva,Cecilia Magbanua
,,,,Angela Flores,,,,,
,,,,Francis Dizon,,,,,
,,,,Rhea Salazar,,,,,
1:00PM-1:30PM,Team NovaLearn,Adaptive LMS & Automated Assessment Engine Module,Analiza Corpuz,Lucas Hernandez,Eduardo Padilla,Ricardo Fontanilla,Jonathan Beltran,Florencia Dela Torre,Cecilia Magbanua
,,,,Camille Bernardo,,,,,
,,,,Danilo Gutierrez,,,,,
,,,,Andrea Salazar,,,,,
1:30PM-2:00PM,Team LogiChain,Central Storage & Smart Inventory Dispatch Module,Analiza Corpuz,Enzo Morales,Eduardo Padilla,Ricardo Fontanilla,Jonathan Beltran,Florencia Dela Torre,Cecilia Magbanua
,,,,Valerie Cruz,,,,,
,,,,Paolo Mercado,,,,,
,,,,Bianca Reyes,,,,,
2:00PM-2:30PM,Team EnerGrid,Campus Power Consumption & Smart Grid Analytics Module,Analiza Corpuz,Giancarlo Diaz,Eduardo Padilla,Ricardo Fontanilla,Jonathan Beltran,Florencia Dela Torre,Cecilia Magbanua
,,,,Rachelle Santos,,,,,
,,,,Marco Dela Cruz,,,,,
,,,,Hannah Flores,,,,,
2:30PM-3:00PM,Team OmniPort,Automated University Procurement & Vendor Quotation Module,Analiza Corpuz,Leandro Garcia,Eduardo Padilla,Ricardo Fontanilla,Jonathan Beltran,Florencia Dela Torre,Cecilia Magbanua
,,,,Kirsten Gomez,,,,,
,,,,Jerome Pineda,,,,,
,,,,Monica Castro,,,,,
3:00PM-3:30PM,Team MediTrack,Pharmacy Dispensing & Clinic Appointment Module,Renato Villanueva,Timothy Aguilar,Eduardo Padilla,Arsenio Macasaet,Teresita Buenaventura,Jonathan Beltran,Cecilia Magbanua
,,,,Clarisse Domingo,,,,,
,,,,Nathaniel Pascual,,,,,
,,,,Fiona Soriano,,,,,
3:30PM-4:00PM,Team EcoRoute,Electric Shuttle Fleet & Route Optimization Module,Renato Villanueva,Oliver Tan,Eduardo Padilla,Arsenio Macasaet,Teresita Buenaventura,Jonathan Beltran,Cecilia Magbanua
,,,,Kaye Tolentino,,,,,
,,,,Derrick Miranda,,,,,
,,,,Althea Fernandez,,,,,
4:00PM-4:30PM,Team BuildSense,Facility Maintenance Ticketing & Preventive Inspection Module,Renato Villanueva,Justin Valenzuela,Eduardo Padilla,Arsenio Macasaet,Teresita Buenaventura,Jonathan Beltran,Cecilia Magbanua
,,,,Alyssa Romero,,,,,
,,,,Vincent Marquez,,,,,
,,,,Danica Sotto,,,,,
4:30PM-5:00PM,Team DataPulse,Institutional Research & Predictive Student Success Module,Renato Villanueva,Gabriel Tan,Eduardo Padilla,Arsenio Macasaet,Teresita Buenaventura,Jonathan Beltran,Cecilia Magbanua
,,,,Chloe Soriano,,,,,
,,,,Pauline Mercado,,,,,
,,,,Rafael Pascual,,,,,
''';

      final bytes = Uint8List.fromList(utf8.encode(scheduleCsv));
      final result = parseScheduleImportFile(bytes: bytes, filename: 'defense_schedule_import.csv');

      expect(result.stage, 'Concept Proposal');
      expect(result.date, 'October 20, 2026');
      expect(result.room, 'Room 301');
      expect(result.rows.length, 16);

      for (final row in result.rows) {
        expect(row.members, hasLength(4));
        expect(row.chair, isNotEmpty);
        expect(row.panelMembers, hasLength(3));
        expect(row.documenter, 'Cecilia Magbanua');
        expect(row.chair, isNot(equals(row.adviser)));
        expect(row.panelMembers, isNot(contains(row.adviser)));
      }
    });
  });
}
