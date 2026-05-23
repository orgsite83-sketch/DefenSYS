import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../config/api_config.dart';

const _primaryColor = Color(0xFF7F1D1D);
const _goldColor = Color(0xFFD97706);

// ── Data models ───────────────────────────────────────────────────────────────

class VaultEntry {
  final String id;
  final String fileName;
  final String? fileUrl;  // Add file URL
  final String teamName;
  final String uploadedBy;
  final String academicYear;
  final String status;
  final String timestamp;
  final String yearLevel;
  final String stage;
  final String type; // 'pit' or 'capstone'
  final String? deliverableLabel;
  final String extractedText;  // PDF content
  final List<String> topics;  // Keywords/topics
  final String summary;  // Summary
  final String category;

  const VaultEntry({
    required this.id,
    required this.fileName,
    this.fileUrl,
    required this.teamName,
    required this.uploadedBy,
    required this.academicYear,
    required this.status,
    required this.timestamp,
    required this.yearLevel,
    required this.stage,
    required this.type,
    this.deliverableLabel,
    this.extractedText = '',
    this.topics = const [],
    this.summary = '',
    this.category = '',
  });

  factory VaultEntry.fromJson(Map<String, dynamic> j) => VaultEntry(
        id: j['id']?.toString() ?? '',
        fileName: (j['file_name'] ?? j['fileName'])?.toString() ?? '',
        fileUrl: j['file_url']?.toString(),
        teamName: (j['team_name'] ?? j['teamName'])?.toString() ?? '—',
        uploadedBy: (j['uploaded_by'] ?? j['uploadedBy'])?.toString() ?? '—',
        academicYear: (j['academic_year'] ?? j['academicYear'])?.toString() ?? '—',
        status: j['status']?.toString() ?? 'Approved',
        timestamp: (j['uploaded_at'] ?? j['timestamp'])?.toString() ?? '',
        yearLevel: (j['year_level'] ?? j['yearLevel'])?.toString() ?? '—',
        stage: j['stage']?.toString() ?? '—',
        type: j['type']?.toString() ?? 'pit',
        deliverableLabel: (j['deliverable_label'] ?? j['deliverableLabel'])?.toString(),
        extractedText: j['extracted_text']?.toString() ?? '',
        topics: (j['topics'] as List?)?.map((e) => e.toString()).toList() ?? [],
        summary: j['summary']?.toString() ?? '',
        category: j['category']?.toString() ?? '',
      );
}

// ── Tab widget ────────────────────────────────────────────────────────────────

class RepositoryTab extends StatefulWidget {
  const RepositoryTab({super.key});

  @override
  State<RepositoryTab> createState() => _RepositoryTabState();
}

class _RepositoryTabState extends State<RepositoryTab> {
  List<VaultEntry> _allEntries = [];
  bool _loading = true;

  String _selectedYear = '';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  Future<String> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token') ?? '';
    } catch (e) {
      print('Error getting token: $e');
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadVault();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVault({String? search}) async {
    try {
      final querySearch = search ?? _searchQuery;
      final vaultUri = Uri.parse('${ApiConfig.digitalVaultUrl}/').replace(
        queryParameters: querySearch.trim().isEmpty
            ? null
            : {'search': querySearch.trim()},
      );
      final token = await _getToken();
      
      print('Fetching vault entries from: $vaultUri');
      print('Token length: ${token.length} chars');
      
      final vaultResponse = await http
          .get(
            vaultUri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));
      
      print('Vault API response: ${vaultResponse.statusCode}');
      
      List<VaultEntry> vaultEntries = [];
      if (vaultResponse.statusCode == 200) {
        try {
          final responseData = json.decode(vaultResponse.body);
          print('Vault response keys: ${responseData.keys}');
          
          final entries = responseData['entries'] as List? ?? [];
          print('Found ${entries.length} vault entries (includes adviser uploads)');
          
          // Log first entry for debugging
          if (entries.isNotEmpty) {
            print('First vault entry keys: ${entries[0].keys}');
            print('First vault entry file_name: ${entries[0]['file_name']}');
            print('First vault entry file_url: ${entries[0]['file_url']}');
            print('First vault entry type: ${entries[0]['type']}');
          }
          
          for (var entry in entries) {
            if (entry is Map<String, dynamic>) {
              vaultEntries.add(VaultEntry.fromJson(entry));
            }
          }
        } catch (e) {
          print('Error parsing vault response: $e');
          print('Response body: ${vaultResponse.body}');
        }
      } else {
        print('Vault API failed: ${vaultResponse.statusCode}');
        print('Response: ${vaultResponse.body}');
      }
      
      // Load team documents uploaded by uploaders (use ApiConfig for Django backend)
      try {
        final docsUrl = '${ApiConfig.teamDocumentsUrl}/';
        print('Fetching team documents from: $docsUrl');
        
        final docsResponse = await http
            .get(
              Uri.parse(docsUrl),
              headers: {
                'Content-Type': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 8));
        
        print('Documents API response: ${docsResponse.statusCode}');
        
        if (docsResponse.statusCode == 200) {
          final docsData = json.decode(docsResponse.body);
          print('Documents data keys: ${docsData.keys}');
          
          final documents = docsData['documents'] as List? ?? [];
          print('Found ${documents.length} team documents');
          
          // Convert team documents to VaultEntry format
          for (var doc in documents) {
            vaultEntries.add(VaultEntry(
              id: 'doc_${doc['id']}',
              fileName: doc['file_name'] ?? 'Unknown',
              fileUrl: doc['file_url']?.toString(),  // Add file_url
              teamName: doc['team_name'] ?? '—',
              uploadedBy: doc['uploaded_by_name'] ?? '—',
              academicYear: '—', // Team documents don't have academic year in current schema
              status: 'Approved', // Show as approved
              timestamp: doc['uploaded_at'] ?? '',
              yearLevel: '—',
              stage: doc['document_type'] ?? 'other',
              type: 'uploader',
              deliverableLabel: doc['description']?.isNotEmpty == true ? doc['description'] : doc['file_name'],
            ));
          }
        } else {
          print('Documents API failed: ${docsResponse.statusCode}');
          print('Response: ${docsResponse.body}');
        }
      } catch (e) {
        // If team documents fail, continue with vault entries only
        print('Failed to load team documents: $e');
      }

      print('Total entries to display: ${vaultEntries.length}');

      // Determine default year/semester from most recent entry
      final years = vaultEntries.map((e) => e.academicYear).where((y) => y != '—').toSet().toList()..sort();
      final defaultYear = years.isNotEmpty ? years.last : '';

      if (mounted) {
        setState(() {
          _allEntries = vaultEntries;
          _selectedYear = defaultYear;
          _loading = false;
        });
      }
    } catch (e) {
      print('Error in _loadVault: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<VaultEntry> get _filtered {
    return _allEntries.where((e) {
      final matchYear = _selectedYear.isEmpty || e.academicYear == _selectedYear;
      return matchYear;
    }).toList();
  }

  /// Machine Learning-powered search with TF-IDF and Naive Bayes
  List<VaultEntry> _mlSearch(String query, List<VaultEntry> entries) {
    if (query.isEmpty) return entries;
    
    final q = query.toLowerCase().trim();
    final queryWords = q.split(RegExp(r'\s+'));
    
    // Calculate IDF (Inverse Document Frequency) for each word in corpus
    final idfScores = _calculateIDF(entries);
    
    // Score each entry using TF-IDF and Naive Bayes
    final scoredEntries = entries.map((entry) {
      double score = 0.0;
      
      // Extract searchable fields
      final fileName = entry.fileName.toLowerCase();
      final teamName = entry.teamName.toLowerCase();
      final deliverableLabel = (entry.deliverableLabel ?? '').toLowerCase();
      final yearLevel = entry.yearLevel.toLowerCase();
      final stage = entry.stage.toLowerCase();
      final type = entry.type.toLowerCase();
      
      // ═══════════════════════════════════════════════════════════════
      // PDF CONTENT EXTRACTION - Search inside PDF text
      // ═══════════════════════════════════════════════════════════════
      final extractedText = entry.extractedText.toLowerCase();
      final topics = entry.topics.map((t) => t.toLowerCase()).toList();
      final summary = entry.summary.toLowerCase();
      
      // Combine all text for document representation (including PDF content)
      final category = entry.category.toLowerCase();
      final document = '$fileName $teamName $deliverableLabel $yearLevel $stage $type $category $extractedText $summary ${topics.join(' ')}';
      final docWords = document.split(RegExp(r'\s+'));
      
      // ═══════════════════════════════════════════════════════════════
      // 1. TF-IDF SCORING (Information Retrieval)
      // ═══════════════════════════════════════════════════════════════
      for (final queryWord in queryWords) {
        if (queryWord.length < 2) continue;
        
        // Calculate Term Frequency (TF) in this document
        final tf = _calculateTF(queryWord, docWords);
        
        // Get Inverse Document Frequency (IDF) from corpus
        final idf = idfScores[queryWord] ?? 0.0;
        
        // TF-IDF score for this term
        final tfidf = tf * idf;
        score += tfidf * 20.0; // Weight TF-IDF contribution
        
        // Field-specific TF-IDF (weighted by field importance)
        if (fileName.contains(queryWord)) {
          final fieldTF = _calculateTF(queryWord, fileName.split(RegExp(r'\s+')));
          score += fieldTF * idf * 15.0; // File name most important
        }
        if (teamName.contains(queryWord)) {
          final fieldTF = _calculateTF(queryWord, teamName.split(RegExp(r'\s+')));
          score += fieldTF * idf * 12.0; // Team name important
        }
        if (deliverableLabel.contains(queryWord)) {
          final fieldTF = _calculateTF(queryWord, deliverableLabel.split(RegExp(r'\s+')));
          score += fieldTF * idf * 10.0; // Deliverable label important
        }
        
        // ═══════════════════════════════════════════════════════════════
        // PDF CONTENT SCORING - Search inside extracted text
        // ═══════════════════════════════════════════════════════════════
        if (extractedText.contains(queryWord)) {
          final fieldTF = _calculateTF(queryWord, extractedText.split(RegExp(r'\s+')));
          score += fieldTF * idf * 25.0; // PDF content VERY important (highest weight)
        }
        
        // Topics matching (auto-extracted keywords)
        if (topics.any((topic) => topic.contains(queryWord))) {
          score += idf * 18.0; // Topics are highly relevant
        }
        
        // Summary matching
        if (summary.contains(queryWord)) {
          final fieldTF = _calculateTF(queryWord, summary.split(RegExp(r'\s+')));
          score += fieldTF * idf * 14.0; // Summary important
        }
      }
      
      // ═══════════════════════════════════════════════════════════════
      // 2. NAIVE BAYES CLASSIFICATION (Probabilistic Matching)
      // ═══════════════════════════════════════════════════════════════
      final bayesScore = _naiveBayesScore(queryWords, entry, entries);
      score += bayesScore * 25.0; // Weight Naive Bayes contribution
      
      // ═══════════════════════════════════════════════════════════════
      // 3. EXACT MATCH BONUS (Highest Priority)
      // ═══════════════════════════════════════════════════════════════
      if (fileName == q) score += 100.0;
      if (teamName == q) score += 90.0;
      if (deliverableLabel == q) score += 85.0;
      if (topics.contains(q)) score += 80.0; // Exact topic match
      
      // ═══════════════════════════════════════════════════════════════
      // 4. PREFIX MATCHING (High Priority)
      // ═══════════════════════════════════════════════════════════════
      if (fileName.startsWith(q)) score += 50.0;
      if (teamName.startsWith(q)) score += 45.0;
      if (deliverableLabel.startsWith(q)) score += 40.0;
      
      // ═══════════════════════════════════════════════════════════════
      // 5. FUZZY MATCHING (Typo Tolerance)
      // ═══════════════════════════════════════════════════════════════
      for (final word in queryWords) {
        if (word.length < 2) continue;
        
        if (_fuzzyMatch(fileName, word)) score += 8.0;
        if (_fuzzyMatch(teamName, word)) score += 7.0;
        if (_fuzzyMatch(deliverableLabel, word)) score += 6.0;
        if (_fuzzyMatch(extractedText, word)) score += 5.0; // Fuzzy match in PDF content
      }
      
      // ═══════════════════════════════════════════════════════════════
      // 6. LEVENSHTEIN DISTANCE (Edit Distance for Typos)
      // ═══════════════════════════════════════════════════════════════
      final fileNameDistance = _levenshteinDistance(fileName, q);
      final teamNameDistance = _levenshteinDistance(teamName, q);
      
      if (fileNameDistance <= 3) score += (10.0 - fileNameDistance * 2);
      if (teamNameDistance <= 3) score += (8.0 - teamNameDistance * 2);
      
      // ═══════════════════════════════════════════════════════════════
      // 7. ACRONYM MATCHING
      // ═══════════════════════════════════════════════════════════════
      if (_matchesAcronym(deliverableLabel, q)) score += 15.0;
      if (_matchesAcronym(stage, q)) score += 12.0;
      
      // ═══════════════════════════════════════════════════════════════
      // 8. RECENCY BIAS (Time-based Ranking)
      // ═══════════════════════════════════════════════════════════════
      try {
        final timestamp = DateTime.parse(entry.timestamp);
        final daysSinceUpload = DateTime.now().difference(timestamp).inDays;
        if (daysSinceUpload <= 7) score += 5.0;
        else if (daysSinceUpload <= 30) score += 2.0;
      } catch (_) {}
      
      return {'entry': entry, 'score': score};
    }).toList();
    
    // Filter out entries with zero score (no match)
    final matchedEntries = scoredEntries.where((item) => item['score'] as double > 0).toList();
    
    // Sort by score (highest first)
    matchedEntries.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    
    // Return sorted entries
    return matchedEntries.map((item) => item['entry'] as VaultEntry).toList();
  }

  /// Calculate TF (Term Frequency) - how often a term appears in document
  double _calculateTF(String term, List<String> document) {
    if (document.isEmpty) return 0.0;
    
    final termCount = document.where((word) => word.toLowerCase() == term.toLowerCase()).length;
    return termCount / document.length;
  }

  /// Calculate IDF (Inverse Document Frequency) - how rare a term is across all documents
  Map<String, double> _calculateIDF(List<VaultEntry> entries) {
    final idfScores = <String, double>{};
    final totalDocs = entries.length;
    
    if (totalDocs == 0) return idfScores;
    
    // Build vocabulary from all documents (including PDF content)
    final vocabulary = <String>{};
    for (final entry in entries) {
      final document = '${entry.fileName} ${entry.teamName} ${entry.deliverableLabel ?? ''} ${entry.yearLevel} ${entry.stage} ${entry.type} ${entry.extractedText} ${entry.summary} ${entry.topics.join(' ')}'.toLowerCase();
      final words = document.split(RegExp(r'\s+'));
      vocabulary.addAll(words.where((w) => w.length >= 2));
    }
    
    // Calculate IDF for each term in vocabulary
    for (final term in vocabulary) {
      // Count documents containing this term
      int docsWithTerm = 0;
      for (final entry in entries) {
        final document = '${entry.fileName} ${entry.teamName} ${entry.deliverableLabel ?? ''} ${entry.yearLevel} ${entry.stage} ${entry.type} ${entry.extractedText} ${entry.summary} ${entry.topics.join(' ')}'.toLowerCase();
        if (document.contains(term)) {
          docsWithTerm++;
        }
      }
      
      // IDF = log(total documents / documents containing term)
      // Add 1 to avoid division by zero
      if (docsWithTerm > 0) {
        idfScores[term] = _log(totalDocs / docsWithTerm);
      }
    }
    
    return idfScores;
  }

  /// Natural logarithm approximation (for IDF calculation)
  double _log(double x) {
    if (x <= 0) return 0.0;
    // Using natural log approximation: ln(x) ≈ (x-1) - (x-1)²/2 + (x-1)³/3 for x near 1
    // For better accuracy, use built-in log if available
    return x > 0 ? (x - 1) / x : 0.0; // Simplified approximation
  }

  /// Naive Bayes Classification Score
  /// Calculates probability that document is relevant given query terms
  double _naiveBayesScore(List<String> queryWords, VaultEntry entry, List<VaultEntry> allEntries) {
    double score = 1.0; // Start with probability 1.0
    
    // Extract document text (including PDF content)
    final document = '${entry.fileName} ${entry.teamName} ${entry.deliverableLabel ?? ''} ${entry.yearLevel} ${entry.stage} ${entry.type} ${entry.extractedText} ${entry.summary} ${entry.topics.join(' ')}'.toLowerCase();
    final docWords = document.split(RegExp(r'\s+'));
    
    // Calculate prior probability P(relevant)
    // Assume 10% of documents are relevant to any query (prior)
    final priorRelevant = 0.1;
    final priorNotRelevant = 0.9;
    
    // For each query word, calculate P(word|relevant) and P(word|not relevant)
    for (final queryWord in queryWords) {
      if (queryWord.length < 2) continue;
      
      // Count occurrences in this document
      final wordInDoc = docWords.where((w) => w == queryWord).length;
      
      // Likelihood: P(word|relevant) - higher if word appears in document
      final pWordGivenRelevant = wordInDoc > 0 ? 0.8 : 0.2;
      
      // P(word|not relevant) - lower if word appears
      final pWordGivenNotRelevant = wordInDoc > 0 ? 0.3 : 0.7;
      
      // Bayes theorem: P(relevant|word) = P(word|relevant) * P(relevant) / P(word)
      // We use likelihood ratio for scoring
      final likelihoodRatio = pWordGivenRelevant / pWordGivenNotRelevant;
      score *= likelihoodRatio;
    }
    
    // Apply prior probability
    score *= priorRelevant / priorNotRelevant;
    
    // Normalize score to 0-1 range using sigmoid function
    return 1.0 / (1.0 + _exp(-score));
  }

  /// Exponential function approximation (for sigmoid in Naive Bayes)
  double _exp(double x) {
    // e^x approximation using Taylor series: e^x ≈ 1 + x + x²/2! + x³/3! + ...
    // Limited to first few terms for performance
    if (x > 10) return 22026.0; // e^10 ≈ 22026
    if (x < -10) return 0.0;
    
    double result = 1.0;
    double term = 1.0;
    
    for (int i = 1; i <= 10; i++) {
      term *= x / i;
      result += term;
      if (term.abs() < 0.0001) break; // Convergence
    }
    
    return result;
  }

  /// Fuzzy matching using character-level similarity
  bool _fuzzyMatch(String text, String pattern) {
    if (pattern.isEmpty) return false;
    if (text.contains(pattern)) return true;
    
    // Check if pattern characters appear in order in text
    int patternIndex = 0;
    for (int i = 0; i < text.length && patternIndex < pattern.length; i++) {
      if (text[i] == pattern[patternIndex]) {
        patternIndex++;
      }
    }
    return patternIndex == pattern.length;
  }

  /// Levenshtein distance for typo tolerance (edit distance)
  int _levenshteinDistance(String s1, String s2) {
    if (s1.length > 50 || s2.length > 50) return 999; // Skip for very long strings
    
    final len1 = s1.length;
    final len2 = s2.length;
    
    if (len1 == 0) return len2;
    if (len2 == 0) return len1;
    
    // Create distance matrix
    final matrix = List.generate(len1 + 1, (i) => List.filled(len2 + 1, 0));
    
    // Initialize first row and column
    for (int i = 0; i <= len1; i++) matrix[i][0] = i;
    for (int j = 0; j <= len2; j++) matrix[0][j] = j;
    
    // Calculate distances
    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,      // deletion
          matrix[i][j - 1] + 1,      // insertion
          matrix[i - 1][j - 1] + cost // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    
    return matrix[len1][len2];
  }

  /// Check if query matches acronym (e.g., "CP" matches "Concept Proposal")
  bool _matchesAcronym(String text, String query) {
    if (query.length < 2) return false;
    
    final words = text.split(RegExp(r'\s+'));
    if (words.length < 2) return false;
    
    final acronym = words.map((w) => w.isNotEmpty ? w[0] : '').join('').toLowerCase();
    return acronym == query.toLowerCase();
  }

  List<String> get _years {
    final y = _allEntries.map((e) => e.academicYear).where((y) => y != '—').toSet().toList()..sort();
    return y.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filtered;
    final isSearching = _searchQuery.isNotEmpty;

    return Column(
      children: [
        // ── Header ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.folder_special, color: _primaryColor, size: 18),
                  SizedBox(width: 8),
                  Text('Digital Vault',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _primaryColor)),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                onChanged: (v) {
                  final query = v.trim();
                  setState(() => _searchQuery = query);
                  _loadVault(search: query);
                },
                decoration: InputDecoration(
                  hintText: 'Smart search: PDF content, topics, file, team...',
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                  prefixIcon: const Icon(Icons.auto_awesome, size: 20, color: _goldColor),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                            _loadVault(search: '');
                          })
                      : const Tooltip(
                          message: 'ML-powered search with PDF content extraction',
                          child: Icon(Icons.psychology, size: 18, color: Colors.grey),
                        ),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              if (!isSearching && _years.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _selectedYear.isEmpty ? null : _selectedYear,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: 'Academic Year',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: _years.map((y) => DropdownMenuItem(
                    value: y,
                    child: Text('SY $y', style: const TextStyle(fontSize: 13)),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedYear = v ?? ''),
                ),
              ],
            ],
          ),
        ),

        // ── Notice ──
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock, color: Colors.amber, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Public vault - view-only access to all team submissions.',
                  style: TextStyle(fontSize: 11, color: Colors.brown),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Count ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                _loading
                    ? 'Loading...'
                    : isSearching
                        ? '${entries.length} result${entries.length != 1 ? "s" : ""} for "$_searchQuery"'
                        : '${entries.length} file${entries.length != 1 ? "s" : ""} found',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),

        // ── List ──
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _primaryColor))
              : entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_off, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            isSearching ? 'No files match "$_searchQuery".' : 'No published files yet.',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: entries.length,
                      itemBuilder: (_, i) => _entryCard(entries[i]),
                    ),
        ),
      ],
    );
  }

  Widget _entryCard(VaultEntry e) {
    final isCapstone = e.type == 'capstone';
    final isUploader = e.type == 'uploader';
    final color = isCapstone ? _primaryColor : (isUploader ? Colors.blue : _goldColor);
    final label = e.deliverableLabel ?? e.fileName;
    final shortName = label.length > 40 ? '${label.substring(0, 40)}…' : label;
    final hasTopics = e.topics.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            e.fileName.toLowerCase().endsWith('.mp4') ? Icons.videocam
              : e.fileName.toLowerCase().endsWith('.zip') ? Icons.folder_zip
              : e.fileName.toLowerCase().endsWith('.ppt') || e.fileName.toLowerCase().endsWith('.pptx') ? Icons.slideshow
              : e.fileName.toLowerCase().endsWith('.doc') || e.fileName.toLowerCase().endsWith('.docx') ? Icons.description
              : Icons.picture_as_pdf,
            color: color, size: 22,
          ),
        ),
        title: Text(shortName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text(e.teamName, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isCapstone ? 'Capstone' : (isUploader ? 'Uploaded' : 'PIT'),
                    style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                if (e.stage != '—' && e.stage.isNotEmpty)
                  Text(e.stage, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                const Spacer(),
                if (e.academicYear != '—')
                  Text(e.academicYear, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            // Display topics as chips
            if (hasTopics) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: e.topics.take(3).map((topic) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _goldColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _goldColor.withOpacity(0.3), width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.label, size: 8, color: _goldColor),
                      const SizedBox(width: 2),
                      Text(
                        topic.length > 15 ? '${topic.substring(0, 15)}…' : topic,
                        style: const TextStyle(fontSize: 8, color: _goldColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.visibility, color: _primaryColor, size: 20),
          tooltip: 'View',
          onPressed: () => _showViewer(e),
        ),
      ),
    );
  }

  void _showViewer(VaultEntry e) async {
    // Get student info from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final studentId = prefs.getString('student_id') ?? prefs.getString('username') ?? 'Unknown';
    final firstName = prefs.getString('first_name') ?? '';
    final lastName = prefs.getString('last_name') ?? '';
    final studentName = '$firstName $lastName'.trim();
    final displayName = studentName.isNotEmpty ? studentName : studentId;
    
    // Use file_url from API if available, otherwise construct from filename
    // Use mediaUrl (without /api) for media files
    final pdfUrl = e.fileUrl != null && e.fileUrl!.isNotEmpty
        ? '${ApiConfig.mediaUrl}${e.fileUrl}'
        : '${ApiConfig.mediaUrl}/media/${e.fileName}';
    
    print('Opening PDF: $pdfUrl');
    print('Viewer: $studentId - $displayName');
    
    if (!mounted) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _PDFViewerScreen(
          fileName: e.deliverableLabel ?? e.fileName,
          pdfUrl: pdfUrl,
          teamName: e.teamName,
          stage: e.stage,
          studentId: studentId,
          studentName: displayName,
        ),
      ),
    );
  }
}

// PDF Viewer Screen
class _PDFViewerScreen extends StatelessWidget {
  final String fileName;
  final String pdfUrl;
  final String teamName;
  final String stage;
  final String studentId;
  final String studentName;

  const _PDFViewerScreen({
    required this.fileName,
    required this.pdfUrl,
    required this.teamName,
    required this.stage,
    required this.studentId,
    required this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName.length > 30 ? '${fileName.substring(0, 30)}...' : fileName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              '$teamName · $stage',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.lock, color: _primaryColor, size: 20),
                      SizedBox(width: 8),
                      Text('Read-Only Document', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                  content: const Text(
                    'This document is available for secure viewing only. '
                    'Downloading and copying are disabled for vault submissions.',
                    style: TextStyle(fontSize: 14),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // PDF Viewer
          SfPdfViewer.network(
            pdfUrl,
            canShowScrollHead: true,
            canShowScrollStatus: true,
            enableDoubleTapZooming: true,
            enableTextSelection: false, // Disable text selection for read-only
            onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to load PDF: ${details.error}'),
                  backgroundColor: Colors.red,
                  action: SnackBarAction(
                    label: 'Retry',
                    textColor: Colors.white,
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => _PDFViewerScreen(
                            fileName: fileName,
                            pdfUrl: pdfUrl,
                            teamName: teamName,
                            stage: stage,
                            studentId: studentId,
                            studentName: studentName,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          
          // Watermark Overlay
          IgnorePointer(
            child: Center(
              child: Transform.rotate(
                angle: -0.5, // Diagonal angle (about -30 degrees)
                child: Opacity(
                  opacity: 0.15,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock,
                        size: 60,
                        color: _primaryColor,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'DIGITAL VAULT',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: _primaryColor,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'READ ONLY',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _primaryColor,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        studentId,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _primaryColor,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        studentName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
