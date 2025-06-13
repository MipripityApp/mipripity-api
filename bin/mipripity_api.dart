// Entry point for the mipripity_api
// This file delegates to server.dart for actual implementation

import 'server.dart' as server;

void main(List<String> arguments) {
  print('Starting Mipripity API server...');
  
  // Pass any command line arguments to the server
  server.main();
  
  print('Server started successfully. Press Ctrl+C to stop.');
}