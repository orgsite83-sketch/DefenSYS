import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../config/api_config.dart';
import '../../../services/auth_provider.dart';
import '../../../services/authenticated_client.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/buttons/defensys_theme_toggle.dart';
class UploaderDashboard extends ConsumerStatefulWidget {
  const UploaderDashboard({super.key});

  @override
  ConsumerState<UploaderDashboard> createState() => _UploaderDashboardState();
}

class _UploaderDashboardState extends ConsumerState<UploaderDashboard> {
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
    final client = ref.read(authenticatedHttpClientProvider);
    final response = await client.get(
      Uri.parse('${ApiConfig.teamDocumentsUrl}/'),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        _documents = List<Map<String, dynamic>>.from(data['documents'] ?? []);
      });
    }
  }

  Future<void> _loadTeams() async {
    final client = ref.read(authenticatedHttpClientProvider);

    try {
      final response = await client.get(
        Uri.parse('${ApiConfig.baseUrl}/teams/'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final teams = data['teams'] ?? [];
        
        setState(() {
          _teams = List<Map<String, dynamic>>.from(teams);
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load teams: ${response.statusCode}';
        });
      }
    } catch (e) {
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
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: DefensysTokens.surfaceOf(dialogCtx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusXl),
            side: BorderSide(color: DefensysTokens.borderOf(dialogCtx)),
          ),
          title: Text(
            _selectedTeamId != null 
                ? 'Upload to ${_teams.firstWhere((t) => t['id'] == _selectedTeamId)['name']}'
                : 'Upload Document',
            style: DefensysTokens.dialogTitle.copyWith(
              color: DefensysTokens.textPrimaryOf(dialogCtx),
            ),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'File: ${file.name}',
                  style: TextStyle(
                    color: DefensysTokens.textPrimaryOf(dialogCtx),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Size: ${(file.size / 1024 / 1024).toStringAsFixed(2)} MB',
                  style: TextStyle(
                    color: DefensysTokens.textSecondaryOf(dialogCtx),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                if (_teams.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DefensysTokens.isDark(dialogCtx)
                          ? DefensysTokens.warning.withValues(alpha: 0.15)
                          : Colors.orange.shade50,
                      border: Border.all(
                        color: DefensysTokens.isDark(dialogCtx)
                            ? DefensysTokens.warning.withValues(alpha: 0.4)
                            : Colors.orange.shade200,
                      ),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning,
                          color: DefensysTokens.isDark(dialogCtx)
                              ? const Color(0xFFFBBF24)
                              : Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No teams available. Please create teams first.',
                            style: TextStyle(
                              color: DefensysTokens.textPrimaryOf(dialogCtx),
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<int>(
                    dropdownColor: DefensysTokens.surfaceOf(dialogCtx),
                    decoration: InputDecoration(
                      labelText: 'Select Team',
                      filled: true,
                      fillColor: DefensysTokens.isDark(dialogCtx)
                          ? DefensysTokens.mistInputFill
                          : const Color(0xFFF8FAFC),
                      labelStyle: TextStyle(
                        color: DefensysTokens.textSecondaryOf(dialogCtx),
                        fontSize: 13,
                      ),
                      helperStyle: TextStyle(
                        color: DefensysTokens.textSecondaryOf(dialogCtx),
                        fontSize: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: BorderSide(color: DefensysTokens.borderOf(dialogCtx)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: BorderSide(color: DefensysTokens.borderOf(dialogCtx)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: BorderSide(color: DefensysTokens.maroonOf(dialogCtx), width: 1.5),
                      ),
                      helperText: _selectedTeamId != null 
                          ? 'Uploading to current team folder'
                          : null,
                    ),
                    initialValue: selectedTeamId,
                    items: _teams.map((team) {
                      return DropdownMenuItem<int>(
                        value: team['id'],
                        child: Text(
                          '${team['name']} - ${team['level'] ?? 'No level'}',
                          style: TextStyle(
                            color: DefensysTokens.textPrimaryOf(dialogCtx),
                            fontSize: 13,
                          ),
                        ),
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
                  dropdownColor: DefensysTokens.surfaceOf(dialogCtx),
                  decoration: InputDecoration(
                    labelText: 'Document Type',
                    filled: true,
                    fillColor: DefensysTokens.isDark(dialogCtx)
                        ? DefensysTokens.mistInputFill
                        : const Color(0xFFF8FAFC),
                    labelStyle: TextStyle(
                      color: DefensysTokens.textSecondaryOf(dialogCtx),
                      fontSize: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: BorderSide(color: DefensysTokens.borderOf(dialogCtx)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: BorderSide(color: DefensysTokens.borderOf(dialogCtx)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: BorderSide(color: DefensysTokens.maroonOf(dialogCtx), width: 1.5),
                    ),
                  ),
                  initialValue: selectedDocType,
                  items: [
                    DropdownMenuItem(
                      value: 'proposal',
                      child: Text('Project Proposal', style: TextStyle(color: DefensysTokens.textPrimaryOf(dialogCtx), fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: 'documentation',
                      child: Text('Documentation', style: TextStyle(color: DefensysTokens.textPrimaryOf(dialogCtx), fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: 'presentation',
                      child: Text('Presentation', style: TextStyle(color: DefensysTokens.textPrimaryOf(dialogCtx), fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: 'report',
                      child: Text('Report', style: TextStyle(color: DefensysTokens.textPrimaryOf(dialogCtx), fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text('Other', style: TextStyle(color: DefensysTokens.textPrimaryOf(dialogCtx), fontSize: 13)),
                    ),
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
                  style: TextStyle(
                    color: DefensysTokens.textPrimaryOf(dialogCtx),
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'Enter document description',
                    filled: true,
                    fillColor: DefensysTokens.isDark(dialogCtx)
                        ? DefensysTokens.mistInputFill
                        : const Color(0xFFF8FAFC),
                    labelStyle: TextStyle(
                      color: DefensysTokens.textSecondaryOf(dialogCtx),
                      fontSize: 13,
                    ),
                    hintStyle: TextStyle(
                      color: DefensysTokens.textSecondaryOf(dialogCtx),
                      fontSize: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: BorderSide(color: DefensysTokens.borderOf(dialogCtx)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: BorderSide(color: DefensysTokens.borderOf(dialogCtx)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: BorderSide(color: DefensysTokens.maroonOf(dialogCtx), width: 1.5),
                    ),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: DefensysTokens.textSecondaryOf(dialogCtx)),
              ),
            ),
            FilledButton(
              onPressed: (selectedTeamId == null || _teams.isEmpty)
                  ? null
                  : () => Navigator.pop(dialogCtx, true),
              style: FilledButton.styleFrom(
                backgroundColor: DefensysTokens.maroonOf(dialogCtx),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                ),
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
      final client = ref.read(authenticatedHttpClientProvider);
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.teamDocumentsUrl}/upload/'),
      );

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

      final response = await client.sendAuthenticated(request);
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
      backgroundColor: DefensysTokens.backgroundOf(context),
      body: Row(
        children: [
          // Permanent Sidebar
          _buildPermanentSidebar(),
          
          // Main Content Area
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: DefensysTokens.maroonOf(context),
                    ),
                  )
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
                                color: DefensysTokens.isDark(context)
                                    ? DefensysTokens.danger.withValues(alpha: 0.15)
                                    : Colors.red.shade50,
                                border: Border.all(
                                  color: DefensysTokens.isDark(context)
                                      ? DefensysTokens.danger.withValues(alpha: 0.4)
                                      : Colors.red.shade200,
                                ),
                                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error,
                                    color: DefensysTokens.isDark(context)
                                        ? const Color(0xFFF87171)
                                        : Colors.red,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        color: DefensysTokens.textPrimaryOf(context),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_successMessage != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: DefensysTokens.isDark(context)
                                    ? DefensysTokens.success.withValues(alpha: 0.15)
                                    : Colors.green.shade50,
                                border: Border.all(
                                  color: DefensysTokens.isDark(context)
                                      ? DefensysTokens.success.withValues(alpha: 0.4)
                                      : Colors.green.shade200,
                                ),
                                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: DefensysTokens.isDark(context)
                                        ? const Color(0xFF4ADE80)
                                        : Colors.green,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _successMessage!,
                                      style: TextStyle(
                                        color: DefensysTokens.textPrimaryOf(context),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Text(
            'No documents uploaded yet',
            style: TextStyle(
              color: DefensysTokens.textSecondaryOf(context),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    final isDark = DefensysTokens.isDark(context);

    return Card(
      color: DefensysTokens.surfaceOf(context),
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        side: BorderSide(color: DefensysTokens.borderOf(context)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            isDark ? const Color(0xFF28272D) : const Color(0xFFF8FAFC),
          ),
          headingTextStyle: DefensysTokens.tableHeader.copyWith(
            color: DefensysTokens.textSecondaryOf(context),
          ),
          dataTextStyle: DefensysTokens.tableCell.copyWith(
            color: DefensysTokens.textPrimaryOf(context),
          ),
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
              DataCell(Text(doc['file_name'] ?? '', style: TextStyle(color: DefensysTokens.textPrimaryOf(context)))),
              DataCell(Text(doc['team_name'] ?? '', style: TextStyle(color: DefensysTokens.textSecondaryOf(context)))),
              DataCell(Text(doc['document_type'] ?? '', style: TextStyle(color: DefensysTokens.textSecondaryOf(context)))),
              DataCell(Text('${doc['file_size_mb']} MB', style: TextStyle(color: DefensysTokens.textSecondaryOf(context)))),
              DataCell(Text(doc['uploaded_by_name'] ?? '', style: TextStyle(color: DefensysTokens.textSecondaryOf(context)))),
              DataCell(Text(doc['uploaded_at']?.toString().substring(0, 10) ?? '', style: TextStyle(color: DefensysTokens.textSecondaryOf(context)))),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Text(
            'No teams available',
            style: TextStyle(
              color: DefensysTokens.textSecondaryOf(context),
              fontSize: 14,
            ),
          ),
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
              hintStyle: TextStyle(color: DefensysTokens.textSecondaryOf(context), fontSize: 14),
              filled: true,
              fillColor: DefensysTokens.surfaceOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: DefensysTokens.maroonOf(context), width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              prefixIcon: Icon(Icons.search, color: DefensysTokens.textSecondaryOf(context), size: 22),
            ),
            style: TextStyle(fontSize: 14, color: DefensysTokens.textPrimaryOf(context)),
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
              color: DefensysTokens.textSecondaryOf(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        
        // Folders Grid
        if (filteredTeams.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Text(
                'No teams match the selected filters',
                style: TextStyle(
                  color: DefensysTokens.textSecondaryOf(context),
                  fontSize: 14,
                ),
              ),
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
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
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
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFFFD54F), // Light yellow
                                DefensysTokens.gold, // Darker yellow
                              ],
                            ),
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: DefensysTokens.isDark(context) ? 0.35 : 0.15),
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
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFFFFB300), // Darker yellow-orange
                                  DefensysTokens.gold, // Medium yellow
                                ],
                              ),
                              borderRadius: BorderRadius.only(
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
                                  const Color(0xFFFFF9C4).withValues(alpha: 0.3), // Very light yellow highlight
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
                                  const Color(0xFFFF8F00).withValues(alpha: 0.5), // Dark edge
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
                                color: DefensysTokens.maroonOf(context),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: DefensysTokens.textPrimaryOf(context),
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
                        color: DefensysTokens.textSecondaryOf(context),
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
              Icon(
                Icons.folder_open,
                size: 64,
                color: DefensysTokens.textSecondaryOf(context).withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                'No documents in this folder yet',
                style: TextStyle(
                  color: DefensysTokens.textSecondaryOf(context),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _uploadDocument,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload First Document'),
                style: FilledButton.styleFrom(
                  backgroundColor: DefensysTokens.maroonOf(context),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = DefensysTokens.isDark(context);

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
          color: DefensysTokens.surfaceOf(context),
          elevation: isDark ? 0 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
            side: BorderSide(color: DefensysTokens.borderOf(context)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
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
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: DefensysTokens.textPrimaryOf(context),
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
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    uploadDate,
                    style: TextStyle(
                      fontSize: 10,
                      color: DefensysTokens.textSecondaryOf(context).withValues(alpha: 0.8),
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
    // Implement download: `${ApiConfig.teamDocumentsUrl}/$docId/download/` with bearer token
    // Open in new tab or download — platform-specific implementation
  }

  Future<void> _deleteDocument(int docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: DefensysTokens.surfaceOf(dialogCtx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DefensysTokens.radiusXl),
          side: BorderSide(color: DefensysTokens.borderOf(dialogCtx)),
        ),
        title: Text(
          'Delete Document',
          style: DefensysTokens.dialogTitle.copyWith(
            color: DefensysTokens.textPrimaryOf(dialogCtx),
          ),
        ),
        content: Text(
          'Are you sure you want to delete this document?',
          style: DefensysTokens.dialogContent.copyWith(
            color: DefensysTokens.textSecondaryOf(dialogCtx),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: DefensysTokens.textSecondaryOf(dialogCtx)),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(
              backgroundColor: DefensysTokens.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final client = ref.read(authenticatedHttpClientProvider);
      final response = await client.delete(
        Uri.parse('${ApiConfig.teamDocumentsUrl}/$docId/'),
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
    final isDark = DefensysTokens.isDark(context);
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: isDark ? DefensysTokens.mistPanel : DefensysTokens.maroon,
        border: Border(
          right: BorderSide(
            color: isDark ? DefensysTokens.borderOf(context) : Colors.transparent,
            width: 1,
          ),
        ),
      ),
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
                backgroundColor: isDark ? DefensysTokens.maroonOf(context) : DefensysTokens.gold,
                foregroundColor: isDark ? Colors.white : DefensysTokens.maroon,
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
              padding: const EdgeInsets.only(top: 10),
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
                        color: isDark
                            ? DefensysTokens.mistTextSecondary.withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.5),
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
          
          // Quick Theme Switcher
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Theme',
                  style: TextStyle(
                    color: isDark
                        ? DefensysTokens.mistTextSecondary
                        : const Color(0xFFD1D5DB),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const DefensysThemeToggle(),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Logout
          Container(
            height: 1,
            color: isDark
                ? DefensysTokens.borderOf(context)
                : Colors.white.withValues(alpha: 0.09),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                if (await confirmLogout(context)) {
                  await ref.read(authProvider.notifier).logout();
                }
              },
              hoverColor: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.white.withValues(alpha: 0.05),
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: isDark
                          ? DefensysTokens.textSecondaryOf(context)
                          : const Color(0xFFD1D5DB),
                      size: 18,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Log Out',
                      style: TextStyle(
                        color: isDark
                            ? DefensysTokens.textSecondaryOf(context)
                            : const Color(0xFFD1D5DB),
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
    final isDark = DefensysTokens.isDark(context);
    final activeBg = isDark ? const Color(0xFF28272D) : const Color(0xFF5E0D08);
    final activeColor = isDark ? DefensysTokens.mistTextPrimary : DefensysTokens.gold;
    final inactiveColor = isDark ? DefensysTokens.mistTextSecondary : const Color(0xFFD1D5DB);
    final color = isActive ? activeColor : inactiveColor;
    final borderIndicatorColor = isDark ? DefensysTokens.maroonOf(context) : DefensysTokens.gold;
    final hoverColor = isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.05);
    
    return Material(
      color: isActive ? activeBg : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            border: isActive
                ? Border(
                    left: BorderSide(color: borderIndicatorColor, width: 4),
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
                    color: isDark ? DefensysTokens.maroonOf(context) : DefensysTokens.gold,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: isDark ? Colors.white : DefensysTokens.maroon,
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
