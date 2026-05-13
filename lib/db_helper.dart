import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:csv/csv.dart';

class DatabaseHelper {
  // 单例模式，确保全局只有一个数据库实例
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // 获取数据库实例，如果不存在则初始化
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('touken_tracker_test2.lldb');
    return _database!;
  }

  // 初始化数据库路径并打开
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    // 打开数据库，设置版本号并提供建表回调
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  // 创建数据表结构
  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const boolType = 'INTEGER NOT NULL'; // SQLite 中用 1/0 代表布尔值

    await db.execute('''
CREATE TABLE swords (
  id $idType,
  name $textType,
  type $textType,
  is_kiwame $boolType,
  obtained $boolType,
  hurt $boolType,
  true_sword $boolType,
  internal_affairs $boolType,
  light_clothes $boolType,
  ran9 $boolType,
  image_path TEXT -- 新增字段：自定义图片路径，允许用户为每把刀设置个性化头像
  )
''');
  }

  // 将 CSV 数据导入 SQLite（仅在首次运行时调用）
  Future<void> importCsvToDatabase() async {
    final db = await instance.database;
    
    // 检查表是否为空，如果已经有数据则跳过，保护用户进度
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM swords'));
    if (count != null && count > 0) {
      print('数据库已存在数据，跳过 CSV 导入。');
      return;
    }

    print('首次运行：开始从 CSV 导入初始数据...');
    
    try {
      // 1. 读取 Assets 中的 CSV 文件
      final rawData = await rootBundle.loadString('assets/data.csv');
      
      // 2. 解析 CSV (逗号分隔，允许换行)
      List<List<dynamic>> listData = Csv().decode(rawData);
      
      // 3. 跳过表头 (索引 0)，开始遍历每一行数据
      for (int i = 1; i < listData.length; i++) {
        var row = listData[i];
        
        // 防呆机制：如果遇到空行，直接跳过
        if (row.isEmpty || row.length < 10) continue;

        // 核心：基于最新 sword_sheet.csv 的列索引进行解析
        // 0:名称, 1:编号, 2:乱9, 3:内番, 4:刀种, 5:受伤, 6:极/初, 7:真剑, 8:获得, 9:轻装
        
        int id = int.tryParse(row[1].toString().trim()) ?? 0;
        if (id == 0) continue; // 跳过没有有效编号的行
        
        String name = row[0].toString().trim();
        String type = row[4].toString().trim();
        bool isKiwame = row[6].toString().trim() == '极';
        
        // 辅助函数：将表格里的 'TRUE'/'FALSE' 转换为 SQLite 需要的 1 和 0
        int parseBool(dynamic val) => val.toString().trim().toUpperCase() == 'TRUE' ? 1 : 0;
        
        int ran9 = parseBool(row[2]);
        int internalAffairs = parseBool(row[3]);
        int hurt = parseBool(row[5]);
        int trueSword = parseBool(row[7]);
        int obtained = parseBool(row[8]);
        int lightClothes = parseBool(row[9]);

        // 4. 将清洗好的数据插入数据库
        await db.insert('swords', {
          'id': id,
          'name': name,
          'type': type,
          'is_kiwame': isKiwame ? 1 : 0,
          'obtained': obtained,
          'hurt': hurt,
          'true_sword': trueSword,
          'internal_affairs': internalAffairs,
          'light_clothes': lightClothes,
          'ran9': ran9,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      
      print('CSV 数据导入成功！刀帐初始化完毕。');
    } catch (e) {
      print('导入 CSV 时发生致命错误: $e');
    }
  }

  // 获取所有刀剑的列表 (用于在 UI 上显示)
  Future<List<Map<String, dynamic>>> getAllSwords() async {
    final db = await instance.database;
    // 按照编号升序排列
    return await db.query('swords', orderBy: 'id ASC');
  }

  // 核心功能：更新某一把刀的特定状态 (例如：打勾"获得")
  Future<int> updateSwordStatus(int id, String fieldName, bool value) async {
    final db = await instance.database;
    return await db.update(
      'swords',
      {fieldName: value ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 插入一把自定义新刀
  Future<void> insertSword(Map<String, dynamic> row) async {
    final db = await instance.database;
    // 使用 replace，如果填了重复的编号，会覆盖原来的数据
    await db.insert('swords', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // 删除一把刀
  Future<void> deleteSword(int id) async {
    final db = await instance.database;
    await db.delete('swords', where: 'id = ?', whereArgs: [id]);
  }

  // 专门用来更新刀剑图片路径的方法
  Future updateSwordImage(int id, String imagePath) async {
    final db = await instance.database;
    return await db.update(
      'swords',
      {'image_path': imagePath},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 关闭数据库释放资源
  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
