import 'package:flutter/material.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'db_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //判断如果是Windows就切桥接引擎
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const ToukenTrackerApp());
}

class ToukenTrackerApp extends StatelessWidget {
  const ToukenTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '刀帐 Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        scaffoldBackgroundColor: Colors.grey.shade50,
      ),
      home: const SwordGalleryScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SwordGalleryScreen extends StatefulWidget {
  const SwordGalleryScreen({super.key});

  @override
  State<SwordGalleryScreen> createState() => _SwordGalleryScreenState();
}

class _SwordGalleryScreenState extends State<SwordGalleryScreen> {
  // 存放从数据库拿到的所有数据
  List<Map<String, dynamic>> _allSwords = [];
  // 存放经过搜索和筛选后要在界面上显示的数据
  List<Map<String, dynamic>> _displayedSwords = [];
  bool _isLoading = true;

  // --- 筛选与搜索状态 ---
  String _searchQuery = '';
  int? _filterObtained; // null: 全部, 1: 已获得, 0: 未获得
  int? _filterKiwame; // null: 全部, 1: 极, 0: 初

  // 新增的其他状态筛选
  int? _filterHurt;
  int? _filterTrueSword;
  int? _filterInternalAffairs;
  int? _filterLightClothes;
  int? _filterRan9;

  final Set<String> _selectedTypes = {}; // 选中的刀种，为空代表全选

  // 新增的排序状态
  String _currentSort = 'id_asc'; // id_asc, id_desc, name_asc, name_desc

  // 快捷判断当前是否处于“已筛选”或“已改变排序”的状态
  bool get _isFilterActive =>
      _filterObtained != null ||
      _filterKiwame != null ||
      _filterHurt != null ||
      _filterTrueSword != null ||
      _filterInternalAffairs != null ||
      _filterLightClothes != null ||
      _filterRan9 != null ||
      _selectedTypes.isNotEmpty ||
      _currentSort != 'id_asc'; // 如果你想排序改变时也亮起蓝灯，就加上这行

  // --- 视图状态 ---
  bool _isGridView = true; // true 为网格模式，false 为列表模式
  // 刀剑乱舞所有常规刀种
  final List<String> _allTypes = [
    '短刀',
    '胁差',
    '打刀',
    '太刀',
    '大太刀',
    '枪',
    '薙刀',
    '剑',
  ];

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await DatabaseHelper.instance.importCsvToDatabase();
    _loadData();
  }

  // 从数据库加载全量数据，并执行一次筛选逻辑
  Future<void> _loadData() async {
    final data = await DatabaseHelper.instance.getAllSwords();
    setState(() {
      _allSwords = data;
      _applyFilters();
      _isLoading = false;
    });
  }

  // 核心逻辑：根据当前的搜索词、筛选条件和排序方式，实时处理列表
  void _applyFilters() {
    setState(() {
      // 1. 先进行过滤
      _displayedSwords = _allSwords.where((sword) {
        // 搜索匹配
        if (_searchQuery.isNotEmpty) {
          final searchLower = _searchQuery.toLowerCase();
          final nameMatch = sword['name'].toString().toLowerCase().contains(
            searchLower,
          );
          final idMatch = sword['id'].toString().contains(searchLower);
          if (!nameMatch && !idMatch) return false;
        }

        // 状态匹配
        if (_filterObtained != null && sword['obtained'] != _filterObtained) {
          return false;
        }
        if (_filterKiwame != null && sword['is_kiwame'] != _filterKiwame) {
          return false;
        }
        if (_selectedTypes.isNotEmpty &&
            !_selectedTypes.contains(sword['type'])) {
          return false;
        }
        if (_filterHurt != null && sword['hurt'] != _filterHurt) return false;
        if (_filterTrueSword != null &&
            sword['true_sword'] != _filterTrueSword) {
          return false;
        }
        if (_filterInternalAffairs != null &&
            sword['internal_affairs'] != _filterInternalAffairs) {
          return false;
        }
        if (_filterLightClothes != null &&
            sword['light_clothes'] != _filterLightClothes) {
          return false;
        }
        if (_filterRan9 != null && sword['ran9'] != _filterRan9) return false;

        return true;
      }).toList();

      // 2. 然后进行排序
      _displayedSwords.sort((a, b) {
        switch (_currentSort) {
          case 'id_desc': // 编号从大到小
            return b['id'].compareTo(a['id']);
          case 'name_asc': // 名字顺序 (A-Z)
            return a['name'].toString().compareTo(b['name'].toString());
          case 'name_desc': // 名字逆序 (Z-A)
            return b['name'].toString().compareTo(a['name'].toString());
          case 'id_asc': // 编号从小到大 (默认)
          default:
            return a['id'].compareTo(b['id']);
        }
      });
    });
  }

  // 打开筛选面板弹窗
  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            // 辅助构建选择芯片 (ChoiceChip)
            Widget buildChoice<T>(
              String label,
              T value,
              T? groupValue,
              Function(T) onSelect,
            ) {
              final isSelected = value == groupValue;
              return ChoiceChip(
                label: Text(label),
                selected: isSelected,
                selectedColor: const Color.fromARGB(255, 208, 207, 220),
                onSelected: (_) => setModalState(() => onSelect(value)),
              );
            }

            // 辅助构建状态单行的快捷方式
            Widget buildStatusRow(
              String title,
              List<String> labels,
              int? currentValue,
              Function(int?) onSelect,
            ) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      buildChoice(
                        labels[0],
                        null,
                        currentValue,
                        onSelect,
                      ), // 对应 null
                      buildChoice(labels[1], 1, currentValue, onSelect), // 对应 1
                      buildChoice(labels[2], 0, currentValue, onSelect), // 对应 0
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '排序与筛选',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              _filterObtained = null;
                              _filterKiwame = null;
                              _filterHurt = null;
                              _filterTrueSword = null;
                              _filterInternalAffairs = null;
                              _filterLightClothes = null;
                              _filterRan9 = null;
                              _selectedTypes.clear();
                              _currentSort = 'id_asc'; // 重置为默认排序
                            });
                            _applyFilters();
                          },
                          child: const Text(
                            '重置 (Reset)',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    // ✨ 核心改变：使用 Flexible 和 SingleChildScrollView 防止选项太多溢出屏幕
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // --- 排序区域 ---
                            const Text(
                              '排序方式',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                buildChoice(
                                  '编号从小到大',
                                  'id_asc',
                                  _currentSort,
                                  (v) => _currentSort = v,
                                ),
                                buildChoice(
                                  '编号从大到小',
                                  'id_desc',
                                  _currentSort,
                                  (v) => _currentSort = v,
                                ),
                                buildChoice(
                                  '名字顺排 (A-Z)',
                                  'name_asc',
                                  _currentSort,
                                  (v) => _currentSort = v,
                                ),
                                buildChoice(
                                  '名字逆排 (Z-A)',
                                  'name_desc',
                                  _currentSort,
                                  (v) => _currentSort = v,
                                ),
                              ],
                            ),
                            const Divider(),

                            // --- 筛选区域 ---
                            buildStatusRow(
                              '图鉴状态',
                              ['全部', '已获得', '未获得'],
                              _filterObtained,
                              (v) => _filterObtained = v,
                            ),
                            buildStatusRow(
                              '形态阶段',
                              ['全部', '极化', '初期'],
                              _filterKiwame,
                              (v) => _filterKiwame = v,
                            ),

                            const Text(
                              '刀种',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              children: _allTypes.map((type) {
                                final isSelected = _selectedTypes.contains(
                                  type,
                                );
                                return FilterChip(
                                  label: Text(type),
                                  selected: isSelected,
                                  selectedColor: Colors.blueGrey.shade100,
                                  onSelected: (bool selected) {
                                    setModalState(() {
                                      if (selected) {
                                        _selectedTypes.add(type);
                                      } else {
                                        _selectedTypes.remove(type);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),

                            // 其他收集状态继续使用 是/否
                            buildStatusRow(
                              '受伤状态 (Hurt)',
                              ['全部', '是', '否'],
                              _filterHurt,
                              (v) => _filterHurt = v,
                            ),
                            buildStatusRow(
                              '真剑必杀 (True Sword)',
                              ['全部', '是', '否'],
                              _filterTrueSword,
                              (v) => _filterTrueSword = v,
                            ),
                            buildStatusRow(
                              '内番 (Internal Affairs)',
                              ['全部', '是', '否'],
                              _filterInternalAffairs,
                              (v) => _filterInternalAffairs = v,
                            ),
                            buildStatusRow(
                              '轻装 (Light Clothes)',
                              ['全部', '是', '否'],
                              _filterLightClothes,
                              (v) => _filterLightClothes = v,
                            ),
                            buildStatusRow(
                              '乱舞 Lv.9',
                              ['全部', '是', '否'],
                              _filterRan9,
                              (v) => _filterRan9 = v,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 确认按钮
                    ElevatedButton(
                      onPressed: () {
                        _applyFilters();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        '完成筛选 (显示 ${_displayedSwords.where((s) {
                          // 预计算一下当前条件下的数量
                          bool match(Map<String, dynamic> sword) {
                            if (_filterObtained != null && sword['obtained'] != _filterObtained) return false;
                            if (_filterKiwame != null && sword['is_kiwame'] != _filterKiwame) return false;
                            if (_filterHurt != null && sword['hurt'] != _filterHurt) return false;
                            if (_filterTrueSword != null && sword['true_sword'] != _filterTrueSword) return false;
                            if (_filterInternalAffairs != null && sword['internal_affairs'] != _filterInternalAffairs) return false;
                            if (_filterLightClothes != null && sword['light_clothes'] != _filterLightClothes) return false;
                            if (_filterRan9 != null && sword['ran9'] != _filterRan9) return false;
                            if (_selectedTypes.isNotEmpty && !_selectedTypes.contains(sword['type'])) return false;
                            return true;
                          }

                          return match(s);
                        }).length} 把)',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDetailSheet(Map<String, dynamic> sword) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SwordDetailSheet(
          sword: sword,
          onStatusChanged: _loadData, // 状态更新后，重新加载数据库并自动应用当前筛选
        );
      },
    );
  }

  // 添加自定义刀剑的弹窗
  void _showAddSwordDialog(BuildContext context) {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    String selectedType = '打刀'; // 默认刀种
    bool isKiwame = false;
    File? selectedImage; // 临时保存选中的图片文件

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('添加新刀剑'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 头像选择区域
                    GestureDetector(
                      onTap: () async {
                        FilePickerResult? result = await FilePicker.pickFiles(
                          type: FileType.image,
                        );
                        if (result != null) {
                          setState(() {
                            selectedImage = File(result.files.single.path!);
                          });
                        }
                      },
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: selectedImage != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  selectedImage!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo, color: Colors.grey),
                                  SizedBox(height: 4),
                                  Text(
                                    '上传图片',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: idController,
                      decoration: const InputDecoration(
                        labelText: '编号 (必须是纯数字)',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '刀名'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(labelText: '刀种'),
                      items: _allTypes.map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => selectedType = value!),
                    ),
                    SwitchListTile(
                      title: const Text('是否为极化?'),
                      value: isKiwame,
                      onChanged: (value) => setState(() => isKiwame = value),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final id = int.tryParse(idController.text);
                    if (id == null || nameController.text.isEmpty) return;

                    String? finalImagePath;
                    // 如果用户选了图片，将其拷贝到应用本地目录
                    if (selectedImage != null) {
                      final docDir = await getApplicationDocumentsDirectory();
                      final appDir = Directory(
                        p.join(docDir.path, 'ToukenTracker_Images'),
                      );
                      if (!await appDir.exists()) {
                        await appDir.create(recursive: true);
                      }
                      // 提取文件后缀名 (比如 .jpg, .png)
                      final extension = p.extension(selectedImage!.path);
                      // 重命名为 编号_时间戳 以防重复
                      final newFileName =
                          '${id}_${DateTime.now().millisecondsSinceEpoch}$extension';
                      final savedImage = await selectedImage!.copy(
                        p.join(appDir.path, newFileName),
                      );
                      finalImagePath = savedImage.path; // 获取最终的本地绝对路径
                    }

                    // 构建新数据 (包含路径)
                    final newSword = {
                      'id': id,
                      'name': nameController.text.trim(),
                      'type': selectedType,
                      'is_kiwame': isKiwame ? 1 : 0,
                      'obtained': 0,
                      'hurt': 0,
                      'true_sword': 0,
                      'internal_affairs': 0,
                      'light_clothes': 0,
                      'ran9': 0,
                      'image_path': finalImagePath, // ✨ 存入数据库
                    };

                    await DatabaseHelper.instance.insertSword(newSword);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    _initApp(); // 重新加载列表
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 统一处理头像显示的辅助函数
  Widget _buildAvatarImage(Map<String, dynamic> sword, {double width = 150}) {
    // 如果数据库里有自定义图片路径，并且文件真实存在
    if (sword['image_path'] != null &&
        sword['image_path'].toString().isNotEmpty) {
      final file = File(sword['image_path']);
      if (file.existsSync()) {
        return Image.file(file, width: width, fit: BoxFit.cover);
      }
    }
    // 否则退回使用默认 assets
    return Image.asset(
      'assets/avatars/${sword['id']}.png',
      cacheWidth: width.toInt(),
      fit: BoxFit.cover,
      errorBuilder: (c, e, s) =>
          const Icon(Icons.broken_image, color: Colors.grey, size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '我的刀帐',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          // ✨ 新增：网格/列表切换按钮
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            tooltip: '切换视图',
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView; // 切换状态
              });
            },
          ),
          // 下面是你原本的筛选按钮
          IconButton(
            icon: Icon(
              _isFilterActive ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: _isFilterActive ? Colors.amber : Colors.blue,
            ),
            onPressed: _openFilterSheet,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 常驻搜索栏
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '输入刀名或编号搜索...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) {
                      _searchQuery = value.trim();
                      _applyFilters();
                    },
                  ),
                ),
                // 列表区域
                // 列表区域
                Expanded(
                  child: _displayedSwords.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '没有找到符合条件的刀剑哦\n请尝试调整搜索或筛选条件',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        )
                      // ✨ 核心逻辑：判断当前是网格还是列表？
                      : _isGridView
                      ? GridView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 6, // 一行 6 个
                                childAspectRatio: 0.65,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 12,
                              ),
                          itemCount: _displayedSwords.length,
                          itemBuilder: (context, index) {
                            final sword = _displayedSwords[index];
                            final isObtained = sword['obtained'] == 1;

                            return GestureDetector(
                              onTap: () => _showDetailSheet(sword),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: isObtained
                                              ? Colors.amber.shade600
                                              : Colors.grey.shade300,
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                        color: Colors.white,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: isObtained
                                            ? _buildAvatarImage(sword)
                                            : ColorFiltered(
                                                colorFilter:
                                                    const ColorFilter.matrix([
                                                      0.2126,
                                                      0.7152,
                                                      0.0722,
                                                      0,
                                                      0,
                                                      0.2126,
                                                      0.7152,
                                                      0.0722,
                                                      0,
                                                      0,
                                                      0.2126,
                                                      0.7152,
                                                      0.0722,
                                                      0,
                                                      0,
                                                      0,
                                                      0,
                                                      0,
                                                      1,
                                                      0,
                                                    ]),
                                                child: _buildAvatarImage(
                                                  sword,
                                                  width: 150,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'No.${sword['id']}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey.shade600,
                                      fontFamily: 'Courier',
                                    ),
                                  ),
                                  Text(
                                    sword['name'],
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isObtained
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isObtained
                                          ? Colors.black87
                                          : Colors.grey.shade500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      // ✨ 新增的 ListView (列表模式) 代码
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _displayedSwords.length,
                          itemBuilder: (context, index) {
                            final sword = _displayedSwords[index];
                            final isObtained = sword['obtained'] == 1;

                            return Card(
                              elevation: 1,
                              margin: const EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 4,
                              ),
                              child: ListTile(
                                onTap: () => _showDetailSheet(sword),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isObtained
                                          ? Colors.amber.shade600
                                          : Colors.grey.shade300,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: isObtained
                                        ? _buildAvatarImage(sword, width: 150)
                                        : ColorFiltered(
                                            colorFilter:
                                                const ColorFilter.matrix([
                                                  0.2126,
                                                  0.7152,
                                                  0.0722,
                                                  0,
                                                  0,
                                                  0.2126,
                                                  0.7152,
                                                  0.0722,
                                                  0,
                                                  0,
                                                  0.2126,
                                                  0.7152,
                                                  0.0722,
                                                  0,
                                                  0,
                                                  0,
                                                  0,
                                                  0,
                                                  1,
                                                  0,
                                                ]),
                                            child: _buildAvatarImage(
                                              sword,
                                              width: 150,
                                            ),
                                          ),
                                  ),
                                ),
                                title: Text(
                                  sword['name'],
                                  style: TextStyle(
                                    fontWeight: isObtained
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isObtained
                                        ? Colors.black87
                                        : Colors.grey.shade600,
                                  ),
                                ),
                                subtitle: Text(
                                  'No.${sword['id']} | ${sword['type']} | ${sword['is_kiwame'] == 1 ? "极" : "初"}',
                                  style: TextStyle(color: Colors.grey.shade500),
                                ),
                                trailing: isObtained
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: Colors.amber,
                                      )
                                    : const Icon(
                                        Icons.radio_button_unchecked,
                                        color: Colors.grey,
                                      ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueGrey,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => _showAddSwordDialog(context),
      ),
    );
  }
}

// --------------------------------------------------------
// 底部弹出的状态编辑面板组件 (保持原样)
// --------------------------------------------------------
class SwordDetailSheet extends StatefulWidget {
  final Map<String, dynamic> sword;
  final VoidCallback onStatusChanged;

  const SwordDetailSheet({
    super.key,
    required this.sword,
    required this.onStatusChanged,
  });

  @override
  State<SwordDetailSheet> createState() => _SwordDetailSheetState();
}

class _SwordDetailSheetState extends State<SwordDetailSheet> {
  late Map<String, dynamic> _tempSword;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _tempSword = Map<String, dynamic>.from(widget.sword);
  }

  void _toggleLocalStatus(String fieldName, bool currentValue) {
    setState(() {
      _tempSword[fieldName] = currentValue ? 0 : 1;
      _hasChanges = true;
    });
  }

  Future<void> _saveChanges() async {
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }
    final fieldsToWatch = [
      'obtained',
      'hurt',
      'true_sword',
      'internal_affairs',
      'light_clothes',
      'ran9',
    ];
    for (String field in fieldsToWatch) {
      if (_tempSword[field] != widget.sword[field]) {
        await DatabaseHelper.instance.updateSwordStatus(
          _tempSword['id'],
          field,
          _tempSword[field] == 1,
        );
      }
    }
    widget.onStatusChanged();
    if (mounted) Navigator.pop(context);
  }

  Widget _buildCheckbox(String label, String fieldName) {
    final bool isChecked = _tempSword[fieldName] == 1;
    return CheckboxListTile(
      title: Text(label, style: const TextStyle(fontSize: 15)),
      value: isChecked,
      activeColor: Colors.blueGrey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      onChanged: (bool? value) {
        _toggleLocalStatus(fieldName, isChecked);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16, top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  // ✨ 替换原来的 CircleAvatar，加入可点击更换图片的逻辑
                  GestureDetector(
                    onTap: () async {
                      // 1. 呼出文件选择器
                      FilePickerResult? result = await FilePicker.pickFiles(
                        type: FileType.image,
                      );
                      if (result != null) {
                        // 2. 将图片拷贝到 App 私密目录
                        final docDir = await getApplicationDocumentsDirectory();
                        final appDir = Directory(
                          p.join(docDir.path, 'ToukenTracker_Images'),
                        );
                        if (!await appDir.exists()){
                          await appDir.create(recursive: true);
                        }
                        final selectedFile = File(result.files.single.path!);
                        final extension = p.extension(selectedFile.path);
                        final newFileName =
                            '${_tempSword['id']}_${DateTime.now().millisecondsSinceEpoch}$extension';
                        final savedImage = await selectedFile.copy(
                          p.join(appDir.path, newFileName),
                        );

                        // 3. 更新数据库并立即刷新当前弹窗的 UI
                        await DatabaseHelper.instance.updateSwordImage(
                          _tempSword['id'],
                          savedImage.path,
                        );

                        // 这里的 setState 是弹窗内部的 StatefulBuilder 传进来的更新函数
                        // 如果你的叫 setModalState，请把它改成 setModalState
                        setState(() {
                          _tempSword['image_path'] = savedImage.path;
                        });
                        widget.onStatusChanged(); // 刷新外面的主列表
                      }
                    },
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage:
                              (_tempSword['image_path'] != null &&
                                  _tempSword['image_path']
                                      .toString()
                                      .isNotEmpty &&
                                  File(_tempSword['image_path']).existsSync())
                              ? FileImage(File(_tempSword['image_path']))
                                    as ImageProvider
                              : AssetImage(
                                  'assets/avatars/${_tempSword['id']}.png',
                                ),
                          onBackgroundImageError: (e, s) {},
                          child:
                              (_tempSword['image_path'] == null &&
                                  !File(
                                    'assets/avatars/${_tempSword['id']}.png',
                                  ).existsSync())
                              ? const Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                        // 右下角加一个小的相机提示图标
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.blueGrey,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tempSword['name'],
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_tempSword['type']} | ${_tempSword['is_kiwame'] == 1 ? "极" : "初"}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(), // ✨ 新增：把下面的按钮推到最右边
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      // 弹出确认框
                      bool confirm = await showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('确认删除?'),
                          content: Text('要将 ${_tempSword['name']} 从刀帐中彻底移除吗？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text(
                                '删除',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await DatabaseHelper.instance.deleteSword(
                          _tempSword['id'],
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context); // 关闭底部抽屉
                        widget.onStatusChanged(); // 刷新主列表
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            _buildCheckbox('🌟 获得 (Obtained)', 'obtained'),
            _buildCheckbox('🩸 受伤 (Hurt)', 'hurt'),
            _buildCheckbox('⚔️ 真剑必杀 (True Sword)', 'true_sword'),
            _buildCheckbox('🧹 内番 (Internal Affairs)', 'internal_affairs'),
            _buildCheckbox('👘 轻装 (Light Clothes)', 'light_clothes'),
            _buildCheckbox('🌸 乱舞 Lv.9', 'ran9'),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: ElevatedButton(
                onPressed: _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hasChanges
                      ? Colors.blueGrey
                      : Colors.grey.shade300,
                  foregroundColor: _hasChanges
                      ? Colors.white
                      : Colors.grey.shade600,
                  minimumSize: const Size(double.infinity, 50),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _hasChanges ? '保存更改 (Save)' : '关闭 (Close)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
