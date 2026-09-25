import React, {useState} from 'react';
import {Button, SafeAreaView, Text, View} from 'react-native';

export default function App() {
  const [signedIn, setSignedIn] = useState(false);
  return (
    <SafeAreaView style={{flex: 1, padding: 24, backgroundColor: 'white'}}>
      <Text accessibilityRole="header">Precheck RN Broken</Text>
      <Text>Example account sign-in</Text>
      <View style={{marginTop: 18}}>
        <Button title="Sign in with Example" onPress={() => setSignedIn(true)} />
        <Button title="Restore Purchases" onPress={() => {}} />
        <Button title="Community" onPress={() => {}} />
      </View>
      {signedIn && <Text>Signed in with Example</Text>}
      <Text>No account deletion, Apple sign-in, or UGC report path is provided.</Text>
    </SafeAreaView>
  );
}
