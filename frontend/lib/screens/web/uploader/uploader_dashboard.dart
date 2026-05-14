import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../config/api_config.dart';
import '../../../services/auth_provider.dart';
import '../../../theme/app_theme.dart';
import '../../login_screen.dart';

class UploaderDashboard extends ConsumerStatefulWidget {
  const UploaderDashboard({super.key});

  @override
  ConsumerState<UploaderDashboard> createState() => _UploaderDashboardState();
}

class _UploaderDashboardState extends ConsumerState<UploaderDashboard> {
  static const _maroon = Color(0xFF7F1D1D);
  static const _gold = Color(0xFFD97706);
  
  List<Map<String, dynamic>> _documents = [];
  List<Map<String, dynamic>> _teams = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _successMessage;
  
  // Folder view state
  int? _selectedTeamId;
  String _viewMode = 'folders'; // 'folders' or 'list'
  
  // Filter state
  String _filterTeamName = '';
  late final TextEditingController _teamSearchController;

  @override
  void initState() {
    super.initState();
    _teamSearchController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _teamSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _loadDocuments(),
        _loadTeams(),
      ]);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDocuments() async {
    final authState = ref.read(authProvider);
    final token = authState.token;

    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/documents/'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        _documents = List<Map<String, dynamic>>.from(data['documents'] ?? []);
      });
    }
  }

  Future<void> _loadTeams() async {
    final authState = ref.read(authProvider);
    final token = authState.token;

    print('🔍 Loading teams...');
    print('   API URL: ${ApiConfig.baseUrl}/teams/');
    print('   Token: ${token?.substring(0, 20)}...');

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/teams/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📡 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final teams = data['teams'] ?? [];
        
        setState(() {
          _teams = List<Map<String, dynamic>>.from(teams);
        });
        
        print('✅ Loaded ${_teams.length} teams');
        if (_teams.isNotEmpty) {
          print('   Teams:');
          for (var team in _teams.take(5)) {
            print('   - ${team['id']}: ${team['name']} (${team['level']}) - SY: ${team['schoolYear']}, Sem: ${team['semester']}');
          }
        }
      } else {
        print('❌ Failed to load teams: ${response.statusCode}');
        print('   Response body: ${response.body}');
        setState(() {
          _errorMessage = 'Failed to load teams: ${response.statusCode}';
        });
      }
    } catch (e) {
      print('❌ Error loading teams: $e');
      setState(() {
        _errorMessage = 'Error loading teams: $e';
      });
    }
  }

  Future<void> _uploadDocument() async {
    // Pick file
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'zip'],
    );

    if (result == null) return;

    final file = result.files.first;
    
    // Show upload dialog
    await _showUploadDialog(file);
  }

  Future<void> _showUploadDialog(PlatformFile file) async {
    // Pre-select team if viewing a specific team folder
    int? selectedTeamId = _selectedTeamId;
    String selectedDocType = 'other';
    final descriptionController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_selectedTeamId != null 
              ? 'Upload to ${_teams.firstWhere((t) => t['id'] == _selectedTeamId)['name']}'
              : 'Upload Document'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('File: ${file.name}'),
                Text('Size: ${(file.size / 1024 / 1024).toStringAsFixed(2)} MB'),
                const SizedBox(height: 16),
                if (_teams.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('No teams available. Please create teams first.'),
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: 'Select Team',
                      // Show hint if team is pre-selected
                      helperText: _selectedTeamId != null 
                          ? 'Uploading to current team folder'
                          : null,
                    ),
                    initialValue: selectedTeamId,
                    items: _teams.map((team) {
                      return DropdownMenuItem<int>(
                        value: team['id'],
                        child: Text('${team['name']} - ${team['level'] ?? 'No level'}'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedTeamId = value;
                      });
                    },
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Document Type'),
                  initialValue: selectedDocType,
                  items: const [
                    DropdownMenuItem(value: 'proposal', child: Text('Project Proposal')),
                    DropdownMenuItem(value: 'documentation', child: Text('Documentation')),
                    DropdownMenuItem(value: 'presentation', child: Text('Presentation')),
                    DropdownMenuItem(value: 'report', child: Text('Report')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedDocType = value!;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'Enter document description',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (selectedTeamId == null || _teams.isEmpty)
                  ? null
                  : () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _maroon,
                foregroundColor: _gold,
              ),
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && selectedTeamId != null) {
      await _performUpload(file, selectedTeamId!, selectedDocType, descriptionController.text);
    }
  }

  Future<void> _performUpload(
    PlatformFile file,
    int teamId,
    String docType,
    String description,
  ) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/documents/upload/'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['team_id'] = teamId.toString();
      request.fields['document_type'] = docType;
      request.fields['description'] = description;

      if (file.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ));
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 201) {
        setState(() {
          _successMessage = 'Document uploaded successfully!';
        });
        await _loadDocuments();
        
        // Navigate to the team folder to show the uploaded document
        setState(() {
          _viewMode = 'folders';
          _selectedTeamId = teamId;
        });
      } else {
        final error = json.decode(responseBody);
        setState(() {
          _errorMessage = error['detail'] ?? 'Upload failed';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Upload error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Permanent Sidebar
          _buildPermanentSidebar(),
          
          // Main Content Area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                              if (_errorMessage != null)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    border: Border.all(color: Colors.red.shade200),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error, color: Colors.red),
                                      const SizedBox(width: 12),
                                      Expanded(child: Text(_errorMessage!)),
                                    ],
                                  ),
                                ),
                              if (_successMessage != null)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    border: Border.all(color: Colors.green.shade200),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle, color: Colors.green),
                                      const SizedBox(width: 12),
                                      Expanded(child: Text(_successMessage!)),
                                    ],
                                  ),
                                ),
                              // Content based on view mode
                              if (_viewMode == 'folders')
                                _selectedTeamId == null
                                    ? _buildFolderView()
                                    : _buildTeamDocuments()
                              else
                                _buildDocumentsTable(),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsTable() {
    if (_documents.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Text('No documents uploaded yet'),
        ),
      );
    }

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('File Name')),
            DataColumn(label: Text('Team')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Size')),
            DataColumn(label: Text('Uploaded By')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Actions')),
          ],
          rows: _documents.map((doc) {
            return DataRow(cells: [
              DataCell(Text(doc['file_name'] ?? '')),
              DataCell(Text(doc['team_name'] ?? '')),
              DataCell(Text(doc['document_type'] ?? '')),
              DataCell(Text('${doc['file_size_mb']} MB')),
              DataCell(Text(doc['uploaded_by_name'] ?? '')),
              DataCell(Text(doc['uploaded_at']?.toString().substring(0, 10) ?? '')),
              DataCell(
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download, color: Colors.blue),
                      onPressed: () => _downloadDocument(doc['id']),
                      tooltip: 'Download',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteDocument(doc['id']),
                      tooltip: 'Delete',
                    ),
                  ],
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFolderView() {
    if (_teams.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Text('No teams available'),
        ),
      );
    }

    // Apply filters
    var filteredTeams = _teams.where((team) {
      // Team name filter
      if (_filterTeamName.isNotEmpty) {
        final teamName = (team['name'] ?? '').toString().toLowerCase();
        if (!teamName.contains(_filterTeamName.toLowerCase())) {
          return false;
        }
      }
      
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 400,
          child: TextField(
            controller: _teamSearchController,
            decoration: InputDecoration(
              hintText: 'Search Team',
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.maroon, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade500, size: 22),
            ),
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            onChanged: (value) {
              setState(() {
                _filterTeamName = value;
              });
            },
          ),
        ),
        const SizedBox(height: 16),
        // Results counter
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Showing ${filteredTeams.length} of ${_teams.length} teams',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        
        // Folders Grid
        if (filteredTeams.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Text('No teams match the selected filters'),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              childAspectRatio: 1.0,
            ),
            itemCount: filteredTeams.length,
            itemBuilder: (context, index) {
              final team = filteredTeams[index];
              final teamId = team['id'];
              final teamName = team['name'];
              final teamLevel = team['level'] ?? 'No level';
              
              // Count documents for this team
              final docCount = _documents.where((doc) => doc['team'] == teamId).length;
              
              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedTeamId = teamId;
                  });
                },
                borderRadius: BorderRadius.circular(4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
              // Folder icon (Windows standing folder style)
              Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // Main folder body
                  Container(
                    width: 80,
                    height: 65,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFFFFD54F), // Light yellow
                          const Color(0xFFFFC107), // Darker yellow
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                  // Folder tab (top flap)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      width: 32,
                      height: 14,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFFFB300), // Darker yellow-orange
                            Color(0xFFFFC107), // Medium yellow
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(3),
                          topRight: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  // Folder front highlight
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: 80,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFFFFF9C4).withOpacity(0.3), // Very light yellow highlight
                            Colors.transparent,
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(3),
                          bottomRight: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  // Folder edge (3D effect)
                  Positioned(
                    right: 0,
                    top: 14,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            const Color(0xFFFF8F00).withOpacity(0.5), // Dark edge
                            Colors.transparent,
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(3),
                          bottomRight: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  // Document count badge on folder
                  if (docCount > 0)
                    Positioned(
                      top: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _maroon,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '$docCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Team name
              Text(
                teamName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Team level
              Text(
                teamLevel,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTeamDocuments() {
    final teamDocs = _documents.where((doc) => doc['team'] == _selectedTeamId).toList();
    
    if (teamDocs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            children: [
              Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('No documents in this folder yet'),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _uploadDocument,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload First Document'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _maroon,
                  foregroundColor: _gold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: teamDocs.length,
      itemBuilder: (context, index) {
        final doc = teamDocs[index];
        final fileName = doc['file_name'] ?? 'Unknown';
        final fileSize = doc['file_size_mb'] ?? 0.0;
        final uploadDate = doc['uploaded_at']?.toString().substring(0, 10) ?? '';
        
        return Card(
          elevation: 2,
          child: InkWell(
            onTap: () => _downloadDocument(doc['id']),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getFileIcon(fileName),
                    size: 48,
                    color: _getFileColor(fileName),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    fileName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$fileSize MB',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    uploadDate,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.download, size: 20),
                        onPressed: () => _downloadDocument(doc['id']),
                        tooltip: 'Download',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        onPressed: () => _deleteDocument(doc['id']),
                        tooltip: 'Delete',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: Colors.red,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'zip':
      case 'rar':
        return Icons.folder_zip;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'zip':
      case 'rar':
        return Colors.amber;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Future<void> _downloadDocument(int docId) async {
    // Implement download: `${ApiConfig.baseUrl}/documents/$docId/download/` with bearer token
    // Open in new tab or download — platform-specific implementation
  }

  Future<void> _deleteDocument(int docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: const Text('Are you sure you want to delete this document?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final authState = ref.read(authProvider);
      final token = authState.token;

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/documents/$docId/'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _successMessage = 'Document deleted successfully';
        });
        await _loadDocuments();
        
        // Stay in current view after deletion
        // If we're in a team folder and it becomes empty, stay in the folder
      }
    }
  }

  Widget _buildPermanentSidebar() {
    return Container(
      width: 260,
      color: _maroon,
      child: Column(
        children: [
          // Upload Document Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _uploadDocument,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Upload Document'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _maroon,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ),
          
          
          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 20),
              children: [
                _buildSidebarItem(
                  icon: Icons.folder_outlined,
                  label: 'All Teams',
                  onTap: () {
                    setState(() {
                      _viewMode = 'folders';
                      _selectedTeamId = null;
                    });
                  },
                  isActive: _viewMode == 'folders' && _selectedTeamId == null,
                ),
                const SizedBox(height: 8),
                _buildSidebarItem(
                  icon: Icons.list_outlined,
                  label: 'All Documents',
                  onTap: () {
                    setState(() {
                      _viewMode = 'list';
                      _selectedTeamId = null;
                    });
                  },
                  isActive: _viewMode == 'list',
                ),
                
                // Team folders section
                if (_teams.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      'TEAMS',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  
                  // Individual team folders
                  ...(_teams.where((team) {
                    // Apply filter to sidebar team list
                    if (_filterTeamName.isNotEmpty) {
                      final teamName = (team['name'] ?? '').toString().toLowerCase();
                      if (!teamName.contains(_filterTeamName.toLowerCase())) {
                        return false;
                      }
                    }
                    return true;
                  }).map((team) {
                    final teamId = team['id'];
                    final teamName = team['name'];
                    final docCount = _documents.where((doc) => doc['team'] == teamId).length;
                    
                    return _buildSidebarItem(
                      icon: Icons.folder,
                      label: teamName,
                      badge: docCount > 0 ? docCount.toString() : null,
                      onTap: () {
                        setState(() {
                          _viewMode = 'folders';
                          _selectedTeamId = teamId;
                        });
                      },
                      isActive: _selectedTeamId == teamId,
                    );
                  })),
                ],
              ],
            ),
          ),
          
          // Logout
          Container(height: 1, color: Colors.white.withOpacity(0.09)),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                ref.read(authProvider.notifier).logout();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              hoverColor: Colors.white.withOpacity(0.05),
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Row(
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFD1D5DB),
                      size: 18,
                    ),
                    SizedBox(width: 14),
                    Text(
                      'Log Out',
                      style: TextStyle(
                        color: Color(0xFFD1D5DB),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    String? badge,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    final color = isActive ? const Color(0xFFFFC107) : const Color(0xFFD1D5DB);
    
    return Material(
      color: isActive ? const Color(0xFF5E0D08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.white.withOpacity(0.05),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            border: isActive
                ? const Border(
                    left: BorderSide(color: Color(0xFFFFC107), width: 4),
                  )
                : null,
          ),
          padding: EdgeInsets.only(left: isActive ? 23 : 27, right: 24),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: _maroon,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
