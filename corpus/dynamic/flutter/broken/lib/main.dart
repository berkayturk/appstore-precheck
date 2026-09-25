import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Column(children: [
            Text('Precheck Flutter Broken'),
            Text('Lorem ipsum dolor sit amet.'),
            Text('Account settings have no Delete Account action.'),
            Text('Community feed has no Report Content action.'),
          ]),
        ),
      ),
    ));
