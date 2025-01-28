import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'constants.dart';
import 'drawable.dart';

class AppData extends ChangeNotifier {
  String _responseText = "";
  bool _isLoading = false;
  bool _isInitial = true;
  http.Client? _client;
  IOClient? _ioClient;
  HttpClient? _httpClient;
  StreamSubscription<String>? _streamSubscription;

  final List<Drawable> drawables = [];

  String get responseText =>
      _isInitial ? "..." : (_isLoading ? "Esperant ..." : _responseText);

  bool get isLoading => _isLoading;

  AppData() {
    _httpClient = HttpClient();
    _ioClient = IOClient(_httpClient!);
    _client = _ioClient;
  }

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void addDrawable(Drawable drawable) {
    drawables.add(drawable);
    notifyListeners();
  }

  Future<void> callStream({required String question}) async {
    _responseText = "";
    _isInitial = false;
    setLoading(true);

    try {
      var request = http.Request(
        'POST',
        Uri.parse('http://localhost:11434/api/generate'),
      );

      request.headers.addAll({'Content-Type': 'application/json'});
      request.body =
          jsonEncode({'model': 'llama3.2', 'prompt': question, 'stream': true});

      var streamedResponse = await _client!.send(request);
      _streamSubscription =
          streamedResponse.stream.transform(utf8.decoder).listen((value) {
        var jsonResponse = jsonDecode(value);
        _responseText += jsonResponse['response'];
        notifyListeners();
      }, onError: (error) {
        if (error is http.ClientException &&
            error.message == 'Connection closed while receiving data') {
          _responseText += "\nRequest cancelled.";
        } else {
          _responseText = "Error during streaming: $error";
        }
        setLoading(false);
        notifyListeners();
      }, onDone: () {
        setLoading(false);
      });
    } catch (e) {
      _responseText = "Error during streaming.";
      setLoading(false);
      notifyListeners();
    }
  }

  dynamic fixJsonInStrings(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data.map((key, value) => MapEntry(key, fixJsonInStrings(value)));
    } else if (data is List) {
      return data.map(fixJsonInStrings).toList();
    } else if (data is String) {
      try {
        // Si és JSON dins d'una cadena, el deserialitzem
        final parsed = jsonDecode(data);
        return fixJsonInStrings(parsed);
      } catch (_) {
        // Si no és JSON, retornem la cadena tal qual
        return data;
      }
    }
    // Retorna qualsevol altre tipus sense canvis (números, booleans, etc.)
    return data;
  }

  Future<void> callWithCustomTools({required String userPrompt}) async {
    const apiUrl = 'http://localhost:11434/api/chat';

    _responseText = "";
    _isInitial = false;
    setLoading(true);

    final body = {
      "model": "llama3.2",
      "stream": false,
      "messages": [
        {"role": "user", "content": userPrompt}
      ],
      "tools": tools,
      "format": format
    };

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        print(response.body);

        final jsonResponse = jsonDecode(response.body);
        final content = jsonDecode(jsonResponse['message']['content']);

        if (jsonResponse['message'] != null && content['tool_calls'] != null) {
          final toolCalls = content['tool_calls'] as List<dynamic>;
          for (final toolCall in toolCalls) {
            if (toolCall['function'] != null) {
              _processFunctionCall(toolCall['function']);
            }
          }
        }
        setLoading(false);
      } else {
        setLoading(false);
        throw Exception("Error: ${response.body}");
      }
    } catch (e) {
      print("Error during API call: $e");
      setLoading(false);
    }
  }

// Dibuixa un cercle a la posició 50,100 de radi 34.66
  void cancelRequests() {
    _streamSubscription?.cancel();
    _httpClient?.close(force: true);
    _httpClient = HttpClient();
    _ioClient = IOClient(_httpClient!);
    _client = _ioClient;
    _responseText += "\nRequest cancelled.";
    setLoading(false);
    notifyListeners();
  }

  void _processFunctionCall(Map<String, dynamic> functionCall) {
    final fixedJson = fixJsonInStrings(functionCall);
    final parameters = fixedJson['arguments'];

    Offset? parseOffset(dynamic value) {
      try {
        if (value is Map) {
          return Offset(value['x'].toDouble(), value['y'].toDouble());
        }
      } catch (_) {}
      return null;
    }

    double parseDouble(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }
      return 0.0;
    }

    switch (fixedJson['name']) {
      case 'draw_circle':
        if (parameters['center'] != null && parameters['radius'] != null) {
          final center = parseOffset(parameters['center']);
          final radius = parseDouble(parameters['radius']);
          if (center != null && radius > 0) {
            addDrawable(Circle(center: center, radius: radius));
          } else {
            print("Invalid circle parameters: center=$center, radius=$radius");
          }
        } else {
          print("Missing circle properties: $parameters");
        }
        break;

      case 'draw_line':
        if (parameters['start'] != null && parameters['end'] != null) {
          final start = parseOffset(parameters['start']);
          final end = parseOffset(parameters['end']);
          if (start != null && end != null) {
            addDrawable(Line(start: start, end: end));
          } else {
            print("Invalid line parameters: start=$start, end=$end");
          }
        }
        break;

      case 'draw_rectangle':
        if (parameters['top_left'] != null &&
            parameters['bottom_right'] != null) {
          final topLeft = parseOffset(parameters['top_left']);
          final bottomRight = parseOffset(parameters['bottom_right']);
          if (topLeft != null && bottomRight != null) {
            addDrawable(Rectangle(topLeft: topLeft, bottomRight: bottomRight));
          } else {
            print(
                "Invalid rectangle parameters: topLeft=$topLeft, bottomRight=$bottomRight");
          }
        }
        break;

      default:
        print("Unknown function call: ${fixedJson['name']}");
    }
  }
}
