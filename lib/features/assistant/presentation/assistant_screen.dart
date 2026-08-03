import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_screen.dart';
import '../../chore_tracker/providers/chore_provider.dart';
import '../../store_journal/providers/store_provider.dart';
import '../domain/assistant_models.dart';
import '../services/assistant_orchestrator.dart';
import '../services/deepseek_service.dart';

/// 对话流消息
class _Msg {
  final bool fromUser;
  final String text;
  const _Msg({required this.fromUser, required this.text});
}

/// 智能助手：一句话 / 语音 → DeepSeek 结构化 → 确认后写入家务 / 生活记录
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _listening = false;
  bool _loading = false;
  String? _error;
  AssistantIntent? _pending;
  String? _pendingQuestion;
  List<Map<String, String>> _history = [];
  final List<_Msg> _messages = [];

  static const Map<String, String> _templateLabels = {
    'movie': '影视剧集',
    'dining': '餐饮美食',
    'book': '书籍阅读',
    'place': '景点打卡',
    'shopping': '购物消费',
    'basket': '菜篮子',
    'snack': '零食干货',
    'generic': '通用自定义',
  };

  @override
  void initState() {
    super.initState();
    _messages.add(const _Msg(
      fromUser: false,
      text: '你好，我是智能助手，说一句话即可帮你完成家务打卡或生活记录。\n'
          '例如：「今天和妈妈完成洗碗打卡」「昨晚去麦当劳吃了巨无霸花了45元」'
          '「佳农香蕉3斤12块」「帮我记一笔：佳农香蕉 3 斤 12 元」。\n'
          '也可以让我新建项目、登记菜篮子品类与品牌，确认后才会写入。',
    ));
    _initSpeech();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          // 录音结束/被取消时复位按钮状态
          if (mounted &&
              _listening &&
              (status == 'done' || status == 'notListening')) {
            setState(() => _listening = false);
          }
        },
        onError: (err) {
          if (!mounted) return;
          setState(() => _listening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_speechErrorText(err.errorMsg))),
          );
        },
      );
    } catch (_) {
      _speechReady = false;
    }
    if (mounted) setState(() {});
  }

  /// 语音错误码 → 中文提示
  String _speechErrorText(String code) {
    switch (code) {
      case 'error_no_microphone':
        return '未检测到麦克风，请检查系统录音权限或外接麦克风';
      case 'error_permission':
      case 'error_insufficient_permissions':
        return '未获得麦克风权限，请在系统设置中允许本应用录音';
      case 'error_network':
      case 'error_network_timeout':
        return '网络异常，语音识别失败，请稍后重试';
      case 'error_busy':
      case 'error_recognizer_busy':
        return '语音识别正忙，请稍后再试';
      case 'error_speech_timeout':
        return '没有听到声音，请靠近麦克风再说一次';
      case 'error_no_match':
        return '没有识别到内容，请再说一次';
      case 'error_not_supported':
        return '当前设备不支持系统语音识别，请直接手动输入';
      default:
        return '语音识别失败（$code），请重试或手动输入';
    }
  }

  /// 确保麦克风权限（运行时申请；被永久拒绝时引导去系统设置）
  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    if (result.isGranted) return true;
    if (result.isPermanentlyDenied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('麦克风权限已被永久拒绝，请到系统设置中手动开启')),
      );
      await openAppSettings();
    }
    return false;
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    // 1. 先确保麦克风权限
    if (!await _ensureMicPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未获得麦克风权限，无法使用语音输入')),
        );
      }
      return;
    }
    // 2. 初始化语音识别服务
    if (!_speechReady) await _initSpeech();
    if (!_speechReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前设备不支持系统语音识别，请直接手动输入')),
        );
      }
      return;
    }
    // 3. 语音包缺失时回退系统默认语言，避免强制 zh_CN 启动失败
    var hasZhCn = false;
    try {
      hasZhCn = (await _speech.locales()).any((l) => l.localeId == 'zh_CN');
    } catch (_) {}

    setState(() => _listening = true);
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: hasZhCn ? 'zh_CN' : null,
          partialResults: true,
          cancelOnError: true,
        ),
        onResult: (result) {
          final text = result.recognizedWords;
          if (mounted && text.isNotEmpty) _controller.text = text;
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _listening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('语音启动失败：$e')),
        );
      }
    }
  }

  Future<void> _send([String? override]) async {
    final input = (override ?? _controller.text).trim();
    if (input.isEmpty || _loading) return;
    final settings = context.read<SettingsProvider>();
    if (settings.deepseekApiKey.trim().isEmpty) {
      _showNeedKeyDialog();
      return;
    }
    _controller.clear();
    setState(() {
      _messages.add(_Msg(fromUser: true, text: input));
      _loading = true;
      _error = null;
    });
    _scrollToBottom();
    try {
      final chore = context.read<ChoreProvider>();
      final store = context.read<StoreProvider>();
      final messages = <Map<String, String>>[
        {
          'role': 'system',
          'content': AssistantOrchestrator.buildSystemPrompt(chore: chore, store: store),
        },
        ..._history,
        {'role': 'user', 'content': input},
      ];
      final raw = await DeepSeekService.chat(
        apiKey: settings.deepseekApiKey.trim(),
        messages: messages,
      );
      final intent = parseAssistantIntent(raw);
      final question =
          AssistantOrchestrator.validateMatch(intent, chore: chore, store: store);
      if (!mounted) return;
      setState(() {
        _history = [
          ..._history,
          {'role': 'user', 'content': input},
          {'role': 'assistant', 'content': raw},
        ];
        _pending = intent;
        _pendingQuestion = question;
        _messages.add(_Msg(fromUser: false, text: _describeIntent(intent)));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '调用失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _scrollToBottom();
  }

  Future<void> _confirm() async {
    final intent = _pending;
    if (intent == null || _loading) return;
    setState(() => _loading = true);
    try {
      final chore = context.read<ChoreProvider>();
      final store = context.read<StoreProvider>();
      final question =
          AssistantOrchestrator.validateMatch(intent, chore: chore, store: store);
      final exec = question == null ? intent : _autoResolve(intent, chore, store);
      final result =
          await AssistantOrchestrator.execute(exec, chore: chore, store: store);
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg(fromUser: false, text: result));
        _pending = null;
        _pendingQuestion = null;
        _history = [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = '执行失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _scrollToBottom();
  }

  void _modify() {
    if (_pending == null) return;
    setState(() {
      _pending = null;
      _pendingQuestion = null;
    });
    _focusInput();
  }

  void _cancel() {
    setState(() {
      _pending = null;
      _pendingQuestion = null;
      _history = [];
    });
  }

  /// 校验提示存在时，依据问题语义自动修正动作后执行
  AssistantIntent _autoResolve(
    AssistantIntent intent,
    ChoreProvider chore,
    StoreProvider store,
  ) {
    final title = intent.choreTitle ?? intent.title;
    if (intent.action == AssistantAction.choreLog &&
        title != null &&
        !chore.choreItems.any((c) => c.title == title)) {
      return intent.withAction(AssistantAction.choreNew);
    }
    if (intent.action == AssistantAction.choreNew &&
        title != null &&
        chore.choreItems.any((c) => c.title == title)) {
      return intent.withAction(AssistantAction.choreLog);
    }
    // 菜篮子：品牌与已登记品牌对齐
    if (intent.template == 'basket') {
      final mb = intent.matchedBrand;
      if (mb != null && mb.isNotEmpty && intent.brand != null && intent.brand != mb) {
        return intent.withBrand(mb);
      }
    }
    final name = intent.name ?? intent.matchedName ?? '';
    final exists = store.storeItems.any((s) => s.name == name);
    if (intent.action == AssistantAction.storeCheckin && !exists) {
      final matched = intent.matchedName;
      if (matched != null && matched.isNotEmpty) {
        for (final s in store.storeItems) {
          if (s.name == matched) return intent.withName(s.name);
        }
      }
      return intent.withAction(AssistantAction.storeNewCheckin);
    }
    if (intent.action == AssistantAction.storeNewCheckin && exists) {
      return intent.withAction(AssistantAction.storeCheckin);
    }
    return intent;
  }

  String _describeIntent(AssistantIntent intent) {
    final b = StringBuffer();
    switch (intent.action) {
      case AssistantAction.ask:
      case AssistantAction.reject:
        return intent.reply.isEmpty ? '未理解，请换一种说法。' : intent.reply;
      case AssistantAction.choreLog:
        b.write('家务打卡：${intent.choreTitle ?? intent.title ?? '?'}');
        break;
      case AssistantAction.choreNew:
        b.write('新建家务并打卡：${intent.choreTitle ?? intent.title ?? '?'}');
        break;
      case AssistantAction.storeNew:
        b.write('新建生活项目：${intent.name ?? intent.matchedName ?? '?'}');
        break;
      case AssistantAction.storeCheckin:
        b.write('生活打卡：${intent.name ?? intent.matchedName ?? '?'}');
        break;
      case AssistantAction.storeNewCheckin:
        b.write('新建并打卡：${intent.name ?? intent.matchedName ?? '?'}');
        break;
    }
    if (intent.category != null) b.write('（${intent.category}）');
    final tpl = intent.template;
    if (tpl != null && _templateLabels.containsKey(tpl)) b.write(' · ${_templateLabels[tpl]}');
    if (intent.memberNames.isNotEmpty) {
      b.write(' · 成员：${intent.memberNames.join('、')}');
    }
    if (intent.value != null) b.write(' · 数量：${_fmtNum(intent.value!)}（${intent.unit ?? '次'}）');
    if (intent.qty != null) b.write(' · 份量：${_fmtNum(intent.qty!)}');
    if (intent.price != null) b.write(' · 单价：¥${intent.price!.toStringAsFixed(2)}');
    if (intent.cost != null) b.write(' · 消费：¥${intent.cost!.toStringAsFixed(2)}');
    if (intent.rating != null) b.write(' · 评分：${intent.rating!.toStringAsFixed(1)}');
    if (intent.menuNames.isNotEmpty) b.write(' · 菜品：${intent.menuNames.join('、')}');
    final brand = intent.brand;
    if (brand != null && brand.isNotEmpty) b.write(' · 品牌：$brand');
    final mb = intent.matchedBrand;
    if (mb != null && mb.isNotEmpty) b.write(' · 已登记品牌：$mb');
    final addr = intent.address;
    if (addr != null && addr.isNotEmpty) b.write(' · 位置：$addr');
    final date = intent.date;
    if (date != null && date.isNotEmpty) b.write(' · 时间：$date');
    final memo = intent.memo;
    if (memo != null && memo.isNotEmpty) b.write(' · 备注：$memo');
    return b.toString();
  }

  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  String _actionLabel(AssistantIntent intent) {
    switch (intent.action) {
      case AssistantAction.choreLog:
        return '家务打卡';
      case AssistantAction.choreNew:
        return '新建家务并打卡';
      case AssistantAction.storeCheckin:
        return '生活记录打卡';
      case AssistantAction.storeNew:
        return '新建生活项目';
      case AssistantAction.storeNewCheckin:
        return '新建生活项目并打卡';
      case AssistantAction.ask:
        return '需要追问';
      case AssistantAction.reject:
        return '无法处理';
    }
  }

  void _showNeedKeyDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('未配置 DeepSeek API Key'),
        content: const Text('请先在「设置 → 智能助手（DeepSeek）」中填入 API Key，再使用语音/文字打卡。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后再说'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  void _focusInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(FocusNode());
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final apiConfigured = context
        .watch<SettingsProvider>()
        .deepseekApiKey
        .trim()
        .isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('智能助手'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'API Key 设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF090D16), Color(0xFF111C38), Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(child: _buildConversation()),
              if (!apiConfigured) _buildKeyHintBar(),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversation() {
    final extra = (_loading ? 1 : 0) +
        (_pending != null ? 1 : 0) +
        (_error != null ? 1 : 0);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _messages.length + extra,
      itemBuilder: (ctx, index) {
        if (index < _messages.length) return _buildBubble(_messages[index]);
        var cursor = _messages.length;
        if (_loading) {
          if (index == cursor) return _buildLoadingRow();
          cursor++;
        }
        if (_pending != null && index == cursor) return _buildPendingCard();
        if (_error != null && index == cursor) return _buildErrorBanner();
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF4444).withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFF87171)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error ?? '',
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFFFCA5A5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_Msg msg) {
    final isUser = msg.fromUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF10B981).withAlpha(90)
              : Colors.white.withAlpha(18),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: Border.all(color: Colors.white.withAlpha(isUser ? 40 : 25)),
        ),
        child: Text(
          msg.text,
          style: const TextStyle(fontSize: 14.5, height: 1.45, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildLoadingRow() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('AI 思考中…', style: TextStyle(fontSize: 13, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildKeyHintBar() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withAlpha(26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withAlpha(60)),
      ),
      child: Row(
        children: [
          const Icon(Icons.key, size: 16, color: Color(0xFFFBBF24)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '尚未配置 DeepSeek API Key，语音/文字打卡前请先在设置中填写',
              style: TextStyle(fontSize: 12, color: Color(0xFFFDE68A)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            child: const Text('去配置'),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(14),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic_none),
            color: _listening ? const Color(0xFFEF4444) : const Color(0xFF10B981),
            tooltip: _listening ? '停止录音' : '语音输入',
            onPressed: _toggleListening,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              cursorColor: const Color(0xFF10B981),
              decoration: InputDecoration(
                hintText: '说一句话：今天和妈妈完成洗碗打卡 / 去麦当劳吃了巨无霸花了45元…',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
              ),
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded),
            color: const Color(0xFF10B981),
            tooltip: '发送',
            onPressed: _loading ? null : () => _send(),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCard() {
    final intent = _pending!;
    final question = _pendingQuestion;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withAlpha(16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, size: 18, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Text(
                _actionLabel(intent),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _describeIntent(intent),
            style: const TextStyle(fontSize: 13.5, height: 1.5, color: Colors.white70),
          ),
          if (question != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withAlpha(22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withAlpha(60)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.help_outline, size: 16, color: Color(0xFFFBBF24)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      question,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFFFDE68A)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancel,
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: _modify,
                child: const Text('修改'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                onPressed: _confirm,
                child: const Text('确认执行'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}