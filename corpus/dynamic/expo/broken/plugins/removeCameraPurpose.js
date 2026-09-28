// Deliberately undo the camera module's Info.plist purpose text in this fixture.
const {withInfoPlist} = require('@expo/config-plugins');

module.exports = (config) => withInfoPlist(config, (mod) => {
  delete mod.modResults.NSCameraUsageDescription;
  return mod;
});
