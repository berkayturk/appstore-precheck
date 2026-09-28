import React, {useState} from 'react';
import {Button, SafeAreaView, Text, View} from 'react-native';

export default function App() {
  const [deleted, setDeleted] = useState(false);
  const [restored, setRestored] = useState(false);
  const [moderation, setModeration] = useState('');
  return (
    <SafeAreaView style={{flex: 1, padding: 24, backgroundColor: 'white'}}>
      <Text accessibilityRole="header">Precheck RN Clean</Text>
      <View style={{marginTop: 18}}>
        <Button title="Delete Account" onPress={() => setDeleted(true)} />
        <Button title="Restore Purchases" onPress={() => setRestored(true)} />
        <Button title="Report Content" onPress={() => setModeration('Report submitted')} />
        <Button title="Block Member" onPress={() => setModeration('Member blocked')} />
      </View>
      {deleted && <Text>Account deleted</Text>}
      {restored && <Text>Restore request completed</Text>}
      {!!moderation && <Text>{moderation}</Text>}
    </SafeAreaView>
  );
}
