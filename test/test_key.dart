import 'dart:convert';
import 'dart:io';

void main() async {
  final file = File('.env');
  if (!await file.exists()) {
    print('No .env file found');
    exit(1);
  }
  
  final lines = await file.readAsLines();
  String apiKey = '';
  for (var line in lines) {
    if (line.startsWith('GEMINI_API_KEY=')) {
      apiKey = line.substring('GEMINI_API_KEY='.length).replaceAll("'", "").replaceAll('"', '').trim();
    }
  }
  
  if (apiKey.isEmpty) {
    print('Empty API key');
    exit(1);
  }
  
  print('Testing key: ' + apiKey.substring(0, 10) + '...');
  
  // Testing gemini-1.5-flash as it's the most common free tier model
  final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=' + apiKey);
  
  final requestBody = jsonEncode({
    "contents": [{
      "parts":[{"text": "Say 'ready'"}]
    }]
  });
  
  final client = HttpClient();
  try {
    final request = await client.postUrl(url);
    request.headers.set('Content-Type', 'application/json');
    request.write(requestBody);
    
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    
    print('Status code: ' + response.statusCode.toString());
    print('Response: ' + responseBody);
    
    if (response.statusCode == 200) {
      print('\nSUCCESS! The API key is working and has quota.');
    } else if (response.statusCode == 429) {
      print('\nSTILL QUOTA EXCEEDED (429). You may need to wait or use a different account.');
    } else if (response.statusCode == 400) {
      print('\nBAD REQUEST (400). This often means the API key is invalid or the model name is wrong.');
    }
  } catch (e) {
    print('Error: ' + e.toString());
  } finally {
    client.close();
  }
}
