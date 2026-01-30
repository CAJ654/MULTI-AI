import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Multi-AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MultiAIAssistantHome(),
      debugShowCheckedModeBanner: false, // Remove the debug banner
    );
  }
}

class MultiAIAssistantHome extends StatefulWidget {
  const MultiAIAssistantHome({super.key});

  @override
  State<MultiAIAssistantHome> createState() => _MultiAIAssistantHomeState();
}

class _MultiAIAssistantHomeState extends State<MultiAIAssistantHome> {
  int _interactionCount = 0;

  void _performInteraction() {
    setState(() {
      _interactionCount++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Multi-AI Assistant'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Total interactions with the assistant:',
            ),
            Text(
              '$_interactionCount',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _performInteraction,
        tooltip: 'Interact',
        child: const Icon(Icons.send),
      ),
    );
  }
}