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
      '1,1011,"RIVERA, James",BSIT,M,1st Yr.,OR-1011,7/28/25 11:47 AM,1011@ustp.edu.ph,09170001011\n'
      '2,1012,"LIM, Sofia",BSIT,F,1st Yr.,OR-1012,7/28/25 11:50 AM,1012@ustp.edu.ph,09170001012\n'
      '3,1013,"TORRES, Miguel",BSIT,M,1st Yr.,OR-1013,7/28/25 11:55 AM,1013@ustp.edu.ph,09170001013\n'
      '4,1014,"NGUYEN, Chloe",BSIT,F,1st Yr.,OR-1014,7/28/25 12:01 PM,1014@ustp.edu.ph,09170001014\n'
      '5,1015,"ALCANTARA, Lucas",BSIT,M,1st Yr.,OR-1015,7/28/25 12:10 PM,1015@ustp.edu.ph,09170001015\n'
      '6,1016,"SANTOS, Elena",BSIT,F,1st Yr.,OR-1016,7/28/25 12:15 PM,1016@ustp.edu.ph,09170001016\n'
      '7,1017,"GARCIA, Mateo",BSIT,M,1st Yr.,OR-1017,7/28/25 12:20 PM,1017@ustp.edu.ph,09170001017\n'
      '8,1018,"DIAZ, Olivia",BSIT,F,1st Yr.,OR-1018,7/28/25 12:25 PM,1018@ustp.edu.ph,09170001018\n'
      '9,1019,"CRUZ, Gabriel",BSIT,M,1st Yr.,OR-1019,7/28/25 12:30 PM,1019@ustp.edu.ph,09170001019\n'
      '10,1020,"REYES, Isabella",BSIT,F,1st Yr.,OR-1020,7/28/25 12:35 PM,1020@ustp.edu.ph,09170001020\n'
      '11,1021,"LEE, Daniel",BSIT,M,1st Yr.,OR-1021,7/28/25 12:40 PM,1021@ustp.edu.ph,09170001021\n'
      '12,1022,"MARTINEZ, Ava",BSIT,F,1st Yr.,OR-1022,7/28/25 12:45 PM,1022@ustp.edu.ph,09170001022\n',
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
      '1,2011,"KIM, Darren",BSIT,M,2nd Yr.,OR-2011,7/28/25 11:47 AM,2011@ustp.edu.ph,09170002011\n'
      '2,2012,"CRUZ, Isabel",BSIT,F,2nd Yr.,OR-2012,7/28/25 11:50 AM,2012@ustp.edu.ph,09170002012\n'
      '3,2013,"RAMOS, Noah",BSIT,M,2nd Yr.,OR-2013,7/28/25 11:55 AM,2013@ustp.edu.ph,09170002013\n'
      '4,2014,"FERNANDEZ, Leah",BSIT,F,2nd Yr.,OR-2014,7/28/25 12:01 PM,2014@ustp.edu.ph,09170002014\n'
      '5,2015,"LOPEZ, Nathan",BSIT,M,2nd Yr.,OR-2015,7/28/25 12:10 PM,2015@ustp.edu.ph,09170002015\n'
      '6,2016,"VALENZUELA, Mia",BSIT,F,2nd Yr.,OR-2016,7/28/25 12:15 PM,2016@ustp.edu.ph,09170002016\n'
      '7,2017,"MENDOZA, Leo",BSIT,M,2nd Yr.,OR-2017,7/28/25 12:20 PM,2017@ustp.edu.ph,09170002017\n'
      '8,2018,"CASTILLO, Chloe",BSIT,F,2nd Yr.,OR-2018,7/28/25 12:25 PM,2018@ustp.edu.ph,09170002018\n'
      '9,2019,"AQUINO, Oliver",BSIT,M,2nd Yr.,OR-2019,7/28/25 12:30 PM,2019@ustp.edu.ph,09170002019\n'
      '10,2020,"CORPUZ, Emma",BSIT,F,2nd Yr.,OR-2020,7/28/25 12:35 PM,2020@ustp.edu.ph,09170002020\n'
      '11,2021,"RIVERA, Ethan",BSIT,M,2nd Yr.,OR-2021,7/28/25 12:40 PM,2021@ustp.edu.ph,09170002021\n'
      '12,2022,"SY, Sophia",BSIT,F,2nd Yr.,OR-2022,7/28/25 12:45 PM,2022@ustp.edu.ph,09170002022\n',
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
      '4,4084,"MENDOZA, Ana",BSIT,F,3rd Yr.,OR-4084,7/28/25 12:01 PM,4084@ustp.edu.ph,09170004084\n'
      '5,4085,"GARCIA, Jose",BSIT,M,3rd Yr.,OR-4085,7/28/25 12:10 PM,4085@ustp.edu.ph,09170004085\n'
      '6,4086,"TORRES, Liza",BSIT,F,3rd Yr.,OR-4086,7/28/25 12:15 PM,4086@ustp.edu.ph,09170004086\n'
      '7,4087,"VILLANUEVA, Marco",BSIT,M,3rd Yr.,OR-4087,7/28/25 12:20 PM,4087@ustp.edu.ph,09170004087\n'
      '8,4088,"FLORES, Nina",BSIT,F,3rd Yr.,OR-4088,7/28/25 12:25 PM,4088@ustp.edu.ph,09170004088\n'
      '9,4089,"RAMOS, Diego",BSIT,M,3rd Yr.,OR-4089,7/28/25 12:30 PM,4089@ustp.edu.ph,09170004089\n'
      '10,4090,"CRUZ, Patricia",BSIT,F,3rd Yr.,OR-4090,7/28/25 12:35 PM,4090@ustp.edu.ph,09170004090\n'
      '11,4091,"BAUTISTA, Ryan",BSIT,M,3rd Yr.,OR-4091,7/28/25 12:40 PM,4091@ustp.edu.ph,09170004091\n'
      '12,4092,"AQUINO, Sophia",BSIT,F,3rd Yr.,OR-4092,7/28/25 12:45 PM,4092@ustp.edu.ph,09170004092\n',
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
      '1,4011,"VILLAR, Marcus",BSIT,M,4th Yr.,OR-4011,7/28/25 11:47 AM,4011@ustp.edu.ph,09170004011\n'
      '2,4012,"ONG, Patricia",BSIT,F,4th Yr.,OR-4012,7/28/25 11:50 AM,4012@ustp.edu.ph,09170004012\n'
      '3,4013,"SALAZAR, Ethan",BSIT,M,4th Yr.,OR-4013,7/28/25 11:55 AM,4013@ustp.edu.ph,09170004013\n'
      '4,4014,"CASTILLO, Zoe",BSIT,F,4th Yr.,OR-4014,7/28/25 12:01 PM,4014@ustp.edu.ph,09170004014\n'
      '5,4015,"TORRES, Ryan",BSIT,M,4th Yr.,OR-4015,7/28/25 12:10 PM,4015@ustp.edu.ph,09170004015\n'
      '6,4016,"VILLANUEVA, Nina",BSIT,F,4th Yr.,OR-4016,7/28/25 12:15 PM,4016@ustp.edu.ph,09170004016\n'
      '7,4017,"GARCIA, Diego",BSIT,M,4th Yr.,OR-4017,7/28/25 12:20 PM,4017@ustp.edu.ph,09170004017\n'
      '8,4018,"RAMOS, Patricia",BSIT,F,4th Yr.,OR-4018,7/28/25 12:25 PM,4018@ustp.edu.ph,09170004018\n'
      '9,4019,"BAUTISTA, Carlos",BSIT,M,4th Yr.,OR-4019,7/28/25 12:30 PM,4019@ustp.edu.ph,09170004019\n'
      '10,4020,"SANTOS, Sophia",BSIT,F,4th Yr.,OR-4020,7/28/25 12:35 PM,4020@ustp.edu.ph,09170004020\n'
      '11,4021,"CRUZ, Miguel",BSIT,M,4th Yr.,OR-4021,7/28/25 12:40 PM,4021@ustp.edu.ph,09170004021\n'
      '12,4022,"ALCANTARA, Isabella",BSIT,F,4th Yr.,OR-4022,7/28/25 12:45 PM,4022@ustp.edu.ph,09170004022\n',
};

const Map<String, String> sampleStudentCsvByYear = {
  '1st Year':
      '$studentBulkImportHeader\n'
      '1011,James,Rivera,1011@ustp.edu.ph,student\n'
      '1012,Sofia,Lim,1012@ustp.edu.ph,student\n'
      '1013,Miguel,Torres,1013@ustp.edu.ph,student\n'
      '1014,Chloe,Nguyen,1014@ustp.edu.ph,student\n'
      '1015,Lucas,Alcantara,1015@ustp.edu.ph,student\n'
      '1016,Elena,Santos,1016@ustp.edu.ph,student\n'
      '1017,Mateo,Garcia,1017@ustp.edu.ph,student\n'
      '1018,Olivia,Diaz,1018@ustp.edu.ph,student\n'
      '1019,Gabriel,Cruz,1019@ustp.edu.ph,student\n'
      '1020,Isabella,Reyes,1020@ustp.edu.ph,student\n'
      '1021,Daniel,Lee,1021@ustp.edu.ph,student\n'
      '1022,Ava,Martinez,1022@ustp.edu.ph,student\n',
  '2nd Year':
      '$studentBulkImportHeader\n'
      '2011,Darren,Kim,2011@ustp.edu.ph,student\n'
      '2012,Isabel,Cruz,2012@ustp.edu.ph,student\n'
      '2013,Noah,Ramos,2013@ustp.edu.ph,student\n'
      '2014,Leah,Fernandez,2014@ustp.edu.ph,student\n'
      '2015,Nathan,Lopez,2015@ustp.edu.ph,student\n'
      '2016,Mia,Valenzuela,2016@ustp.edu.ph,student\n'
      '2017,Leo,Mendoza,2017@ustp.edu.ph,student\n'
      '2018,Chloe,Castillo,2018@ustp.edu.ph,student\n'
      '2019,Oliver,Aquino,2019@ustp.edu.ph,student\n'
      '2020,Emma,Corpuz,2020@ustp.edu.ph,student\n'
      '2021,Ethan,Rivera,2021@ustp.edu.ph,student\n'
      '2022,Sophia,Sy,2022@ustp.edu.ph,student\n',
  '3rd Year':
      '$studentBulkImportHeader\n'
      '4081,Carlos,Reyes,4081@ustp.edu.ph,student\n'
      '4082,Maria,Santos,4082@ustp.edu.ph,student\n'
      '4083,Juan,Dela Cruz,4083@ustp.edu.ph,student\n'
      '4084,Ana,Mendoza,4084@ustp.edu.ph,student\n'
      '4085,Jose,Garcia,4085@ustp.edu.ph,student\n'
      '4086,Liza,Torres,4086@ustp.edu.ph,student\n'
      '4087,Marco,Villanueva,4087@ustp.edu.ph,student\n'
      '4088,Nina,Flores,4088@ustp.edu.ph,student\n'
      '4089,Diego,Ramos,4089@ustp.edu.ph,student\n'
      '4090,Patricia,Cruz,4090@ustp.edu.ph,student\n'
      '4091,Ryan,Bautista,4091@ustp.edu.ph,student\n'
      '4092,Sophia,Aquino,4092@ustp.edu.ph,student\n',
  '4th Year':
      '$studentBulkImportHeader\n'
      '4011,Marcus,Villar,4011@ustp.edu.ph,student\n'
      '4012,Patricia,Ong,4012@ustp.edu.ph,student\n'
      '4013,Ethan,Salazar,4013@ustp.edu.ph,student\n'
      '4014,Zoe,Castillo,4014@ustp.edu.ph,student\n'
      '4015,Ryan,Torres,4015@ustp.edu.ph,student\n'
      '4016,Nina,Villanueva,4016@ustp.edu.ph,student\n'
      '4017,Diego,Garcia,4017@ustp.edu.ph,student\n'
      '4018,Patricia,Ramos,4018@ustp.edu.ph,student\n'
      '4019,Carlos,Bautista,4019@ustp.edu.ph,student\n'
      '4020,Sophia,Santos,4020@ustp.edu.ph,student\n'
      '4021,Miguel,Cruz,4021@ustp.edu.ph,student\n'
      '4022,Isabella,Alcantara,4022@ustp.edu.ph,student\n',
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
