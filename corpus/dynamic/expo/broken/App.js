import React from 'react';
import {Button, SafeAreaView, Text} from 'react-native';
import {requestCameraPermissionsAsync} from 'expo-camera';

export default function App() {
  return <SafeAreaView style={{flex: 1, padding: 24, backgroundColor: 'white'}}>
    <Text accessibilityRole="header">Precheck Expo Broken</Text>
    <Text>Lorem ipsum dolor sit amet.</Text>
    <Button title="Restore Purchases" onPress={() => {}} />
    <Button title="Open Camera" onPress={() => { requestCameraPermissionsAsync(); }} />
    <Text>Community posts have no report control.</Text>
  </SafeAreaView>;
}
