/// Student user bulk-import samples.
const studentSampleYearLevels = [
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year',
];

const studentBulkImportHeader = 'id_number,first_name,last_name,email,role';

const Map<String, String> sampleOfficialClassListCsvByYear = {
  '1st Year':
      'OFFICIAL LIST OF ENROLLED STUDENTS\n'
      '2026-2027 1st Semester\n'
      '\n'
      'Subject Code,IT111\n'
      'Subject Title,Introduction to Computing\n'
      'Academic Units,3,Lab Units,1\n'
      'Credit Units,3,Lab Hours,3\n'
      'Mode,Lecture and Laboratory\n'
      'Instructor,Maricel Suarez\n'
      'Class Section,BSIT-1A\n'
      'Year Level,1st Year\n'
      'Schedule(s),M 1:00 PM - 3:00 PM\n'
      '\n'
      '#,Student Number,Full Name,Program,Gender,Level,OR No.,Validation Date,Email,Contact\n'
      '1,4011,"RIVERA, James",BSIT,M,1st Yr.,OR-4011,7/28/25 11:47 AM,4011@ustp.edu.ph,09170004011\n'
      '2,4012,"LIM, Sofia",BSIT,F,1st Yr.,OR-4012,7/28/25 11:50 AM,4012@ustp.edu.ph,09170004012\n'
      '3,4013,"TORRES, Miguel",BSIT,M,1st Yr.,OR-4013,7/28/25 11:55 AM,4013@ustp.edu.ph,09170004013\n'
      '4,4014,"NGUYEN, Chloe",BSIT,F,1st Yr.,OR-4014,7/28/25 12:01 PM,4014@ustp.edu.ph,09170004014\n',
  '2nd Year':
      'OFFICIAL LIST OF ENROLLED STUDENTS\n'
      '2026-2027 1st Semester\n'
      '\n'
      'Subject Code,IT211\n'
      'Subject Title,Data Structures and Algorithms\n'
      'Academic Units,3,Lab Units,1\n'
      'Credit Units,3,Lab Hours,3\n'
      'Mode,Lecture and Laboratory\n'
      'Instructor,Jonathan Beltran\n'
      'Class Section,BSIT-2A\n'
      'Year Level,2nd Year\n'
      'Schedule(s),T 9:00 AM - 12:00 PM\n'
      '\n'
      '#,Student Number,Full Name,Program,Gender,Level,OR No.,Validation Date,Email,Contact\n'
      '1,4021,"KIM, Darren",BSIT,M,2nd Yr.,OR-4021,7/28/25 11:47 AM,4021@ustp.edu.ph,09170004021\n'
      '2,4022,"CRUZ, Isabel",BSIT,F,2nd Yr.,OR-4022,7/28/25 11:50 AM,4022@ustp.edu.ph,09170004022\n'
      '3,4023,"RAMOS, Noah",BSIT,M,2nd Yr.,OR-4023,7/28/25 11:55 AM,4023@ustp.edu.ph,09170004023\n'
      '4,4024,"FERNANDEZ, Leah",BSIT,F,2nd Yr.,OR-4024,7/28/25 12:01 PM,4024@ustp.edu.ph,09170004024\n',
  '3rd Year':
      'OFFICIAL LIST OF ENROLLED STUDENTS\n'
      '2026-2027 1st Semester\n'
      '\n'
      'Subject Code,IT301\n'
      'Subject Title,Project Innovation and Technology 3\n'
      'Academic Units,3,Lab Units,0\n'
      'Credit Units,3,Lab Hours,0\n'
      'Mode,Lecture and Laboratory\n'
      'Instructor,Maricel Suarez\n'
      'Class Section,BSIT-3A\n'
      'Year Level,3rd Year\n'
      'Schedule(s),M 1:00 PM - 3:00 PM\n'
      '\n'
      '#,Student Number,Full Name,Program,Gender,Level,OR No.,Validation Date,Email,Contact\n'
      '1,4081,"REYES, Carlos",BSIT,M,3rd Yr.,OR-4081,7/28/25 11:47 AM,4081@ustp.edu.ph,09170004081\n'
      '2,4082,"SANTOS, Maria",BSIT,F,3rd Yr.,OR-4082,7/28/25 11:50 AM,4082@ustp.edu.ph,09170004082\n'
      '3,4083,"DELA CRUZ, Juan",BSIT,M,3rd Yr.,OR-4083,7/28/25 11:55 AM,4083@ustp.edu.ph,09170004083\n'
      '4,4084,"MENDOZA, Ana",BSIT,F,3rd Yr.,OR-4084,7/28/25 12:01 PM,4084@ustp.edu.ph,09170004084\n',
  '4th Year':
      'OFFICIAL LIST OF ENROLLED STUDENTS\n'
      '2026-2027 1st Semester\n'
      '\n'
      'Subject Code,CAP401\n'
      'Subject Title,Capstone Project 1\n'
      'Academic Units,3,Lab Units,0\n'
      'Credit Units,3,Lab Hours,0\n'
      'Mode,Lecture and Laboratory\n'
      'Instructor,Ricardo Fontanilla\n'
      'Class Section,BSIT-4A\n'
      'Year Level,4th Year\n'
      'Schedule(s),W 8:00 AM - 11:00 AM\n'
      '\n'
      '#,Student Number,Full Name,Program,Gender,Level,OR No.,Validation Date,Email,Contact\n'
      '1,4091,"VILLAR, Marcus",BSIT,M,4th Yr.,OR-4091,7/28/25 11:47 AM,4091@ustp.edu.ph,09170004091\n'
      '2,4092,"ONG, Patricia",BSIT,F,4th Yr.,OR-4092,7/28/25 11:50 AM,4092@ustp.edu.ph,09170004092\n'
      '3,4093,"SALAZAR, Ethan",BSIT,M,4th Yr.,OR-4093,7/28/25 11:55 AM,4093@ustp.edu.ph,09170004093\n'
      '4,4094,"CASTILLO, Zoe",BSIT,F,4th Yr.,OR-4094,7/28/25 12:01 PM,4094@ustp.edu.ph,09170004094\n',
};

const Map<String, String> sampleStudentCsvByYear = {
  '1st Year':
      '$studentBulkImportHeader\n'
      '4011,James,Rivera,4011@ustp.edu.ph,student\n'
      '4012,Sofia,Lim,4012@ustp.edu.ph,student\n'
      '4013,Miguel,Torres,4013@ustp.edu.ph,student\n'
      '4014,Chloe,Nguyen,4014@ustp.edu.ph,student\n',
  '2nd Year':
      '$studentBulkImportHeader\n'
      '4021,Darren,Kim,4021@ustp.edu.ph,student\n'
      '4022,Isabel,Cruz,4022@ustp.edu.ph,student\n'
      '4023,Noah,Ramos,4023@ustp.edu.ph,student\n'
      '4024,Leah,Fernandez,4024@ustp.edu.ph,student\n',
  '3rd Year':
      '$studentBulkImportHeader\n'
      '4081,Carlos,Reyes,4081@ustp.edu.ph,student\n'
      '4082,Maria,Santos,4082@ustp.edu.ph,student\n'
      '4083,Juan,Dela Cruz,4083@ustp.edu.ph,student\n'
      '4084,Ana,Mendoza,4084@ustp.edu.ph,student\n',
  '4th Year':
      '$studentBulkImportHeader\n'
      '4091,Marcus,Villar,4091@ustp.edu.ph,student\n'
      '4092,Patricia,Ong,4092@ustp.edu.ph,student\n'
      '4093,Ethan,Salazar,4093@ustp.edu.ph,student\n'
      '4094,Zoe,Castillo,4094@ustp.edu.ph,student\n',
};

const sampleFacultyCsvTemplate =
    '$studentBulkImportHeader\n'
    'FAC-0001,Ada,Lovelace,ada@ustp.edu.ph,faculty\n';

String sampleStudentCsvForYear(String yearLevel) =>
    (sampleOfficialClassListCsvByYear[yearLevel] ??
            sampleOfficialClassListCsvByYear['3rd Year']!)
        .trim();

String sampleStudentCsvFilenameForYear(String yearLevel) {
  final slug = yearLevel
      .toLowerCase()
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '');
  return 'defensys-official-class-list-sample-$slug.csv';
}
