import 'package:flutter/material.dart';

import 'api_client.dart';

class _ChatMessage {
  const _ChatMessage({required this.text, required this.isUser, this.isError = false});

  final String text;
  final bool isUser;
  final bool isError;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api = ApiClient();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];

  List<ModelInfo> _models = [];
  ModelInfo? _selectedModel;
  String? _loadError;
  bool _loadingModels = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _loadError = null;
    });
    try {
      final models = await _api.fetchModels();
      setState(() {
        _models = models;
        _selectedModel = models.isNotEmpty ? models.first : null;
      });
    } catch (e) {
      setState(() => _loadError = e.toString());
    } finally {
      setState(() => _loadingModels = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final model = _selectedModel;
    if (text.isEmpty || model == null || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _sending = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final reply = await _api.sendChat(model: model.id, message: text);
      setState(() => _messages.add(_ChatMessage(text: reply, isUser: false)));
    } catch (e) {
      setState(() => _messages.add(_ChatMessage(text: e.toString(), isUser: false, isError: true)));
    } finally {
      setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi-AI'),
        actions: [
          if (!_loadingModels && _loadError == null) _buildModelDropdown(),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (!_loadingModels && _loadError == null) _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingModels) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load models: $_loadError', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadModels, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(child: Text('Pick a model above and say hello.'));
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
    );
  }

  Widget _buildModelDropdown() {
    return DropdownButton<ModelInfo>(
      value: _selectedModel,
      dropdownColor: Theme.of(context).colorScheme.surface,
      underline: const SizedBox.shrink(),
      items: _models
          .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
          .toList(),
      onChanged: _sending ? null : (m) => setState(() => _selectedModel = m),
    );
  }

  Widget _buildMessageBubble(_ChatMessage message) {
    final alignment = message.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = message.isError
        ? Colors.red.shade100
        : message.isUser
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.secondaryContainer;

    return Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Text(message.text),
      ),
    );
  }

  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_sending,
              decoration: const InputDecoration(hintText: 'Message a model…', border: OutlineInputBorder()),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: _sending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            onPressed: _sending ? null : _send,
          ),
        ],
      ),
    );
  }
}
