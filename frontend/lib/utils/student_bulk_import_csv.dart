/// Student user bulk-import samples. Matches `sample_file/demo_students_*`.
const studentSampleYearLevels = [
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year',
];

const studentBulkImportHeader = 'id_number,first_name,last_name,email,role';

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
    '2024-0001,Juan,Dela Cruz,juan@ustp.edu.ph,student\n'
    'FAC-0001,Ada,Lovelace,ada@ustp.edu.ph,faculty\n';

String sampleStudentCsvForYear(String yearLevel) =>
    (sampleStudentCsvByYear[yearLevel] ?? sampleStudentCsvByYear['3rd Year']!)
        .trim();

String sampleStudentCsvFilenameForYear(String yearLevel) {
  final slug = yearLevel
      .toLowerCase()
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '');
  return 'defensys-students-sample-$slug.csv';
}
