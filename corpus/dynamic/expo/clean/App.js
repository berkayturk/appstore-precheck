import React, {useState} from 'react';
import {Button, SafeAreaView, Text} from 'react-native';
import {CameraView, requestCameraPermissionsAsync} from 'expo-camera';

export default function App() {
  const [status, setStatus] = useState('Ready');
  const [cameraOpen, setCameraOpen] = useState(false);
  return <SafeAreaView style={{flex: 1, padding: 24, backgroundColor: 'white'}}>
    <Text accessibilityRole="header">Precheck Expo Clean</Text>
    <Button title="Delete Account" onPress={() => setStatus('Account deleted')} />
    <Button title="Restore Purchases" onPress={() => setStatus('Restore request completed')} />
    <Button title="Report Content" onPress={() => setStatus('Report submitted')} />
    <Button title="Open Camera" onPress={async () => {
      const permission = await requestCameraPermissionsAsync();
      if (permission.granted) setCameraOpen(true);
    }} />
    {cameraOpen && <CameraView style={{height: 160}} />}
    <Text>{status}</Text>
  </SafeAreaView>;
}
