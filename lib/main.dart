import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber)
      ),
      home: const MyHomePage(title: 'Repo Notes'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const String _greeting = 'Hello, World!';
  String _memo = '';
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _showToast() {
    String inputText = _textController.text;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$inputText'),
        duration: const Duration(seconds: 2),
      )
    );

    _textController.clear();
  }

  void _saveText() {
    String inputText = _textController.text;

  // setStateを呼び出して、インプットボックスの下部にテキストを表示するための変数を更新
    setState(() {
      _memo = inputText;
    });

    _textController.clear();

  }


  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                _greeting,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _textController,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Enter your name',
                )
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _saveText,
                child: const Text('保存'),
              ),
              SizedBox(height: 16),
              Text(
                _memo,
                style: TextStyle(fontSize: 18),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showToast,
        tooltip: 'Show Toast',
        child: const Icon(Icons.add),
      ),
    );
  }
}
