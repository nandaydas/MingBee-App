import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dating_app/datas/user.dart';
import 'package:dating_app/models/app_model.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:dating_app/helpers/app_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:dating_app/plugins/geoflutterfire/geoflutterfire.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:place_picker/place_picker.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dating_app/constants/constants.dart';
import 'package:firebase_auth/firebase_auth.dart' as fire_auth;

class UserModel extends Model {
  /// Final Variables
  ///
  final _firebaseAuth = fire_auth.FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storageRef = FirebaseStorage.instance;
  final _fcm = FirebaseMessaging.instance;
  final _appHelper = AppHelper();

  /// Initialize geoflutterfire instance
  final _geo = Geoflutterfire();

  /// Other variables
  ///
  late User user;
  bool userIsVip = false;
  bool isLoading = false;
  String activeVipId = '';
  bool showRestoreVipMsg = false;

  // Update the state
  void updateRestoreVipMsg(bool value) {
    showRestoreVipMsg = value;
    notifyListeners();
    debugPrint('updateRestoreVipMsg() -> $value');
  }
  
  /// Create Singleton factory for [UserModel]
  ///
  static final UserModel _userModel = UserModel._internal();
  factory UserModel() {
    return _userModel;
  }
  UserModel._internal();
  // End

  ///*** FirebaseAuth and Firestore Methods ***///

  /// Get Firebase User
  /// Attempt to get previous logged in user
  fire_auth.User? get getFirebaseUser => _firebaseAuth.currentUser;

  /// Get user from database => [DocumentSnapshot<Map<String, dynamic>>]
  Future<DocumentSnapshot<Map<String, dynamic>>> getUser(String userId) async {
    return await _firestore.collection(C_USERS).doc(userId).get();
  }

  /// Get user object => [User]
  Future<User> getUserObject(String userId) async {
    /// Get Updated user info
    final DocumentSnapshot<Map<String, dynamic>> userDoc =
        await UserModel().getUser(userId);

    /// return user object
    return User.fromDocument(userDoc.data()!);
  }

  /// Get user from database to listen changes => stream of [DocumentSnapshot<Map<String, dynamic>>]
  Stream<DocumentSnapshot<Map<String, dynamic>>> getUserStream() {
    return _firestore.collection(C_USERS).doc(getFirebaseUser!.uid).snapshots();
  }

  /// Update user object [User]
  void updateUserObject(Map<String, dynamic> userDoc) {
    user = User.fromDocument(userDoc);
    notifyListeners();
    debugPrint('User object -> updated!');
  }

  /// Update user data
  Future<void> updateUserData(
      {required String userId, required Map<String, dynamic> data}) async {
    // Update user data
    _firestore.collection(C_USERS).doc(userId).update(data);
  }

  /// Update user device token and
  /// subscribe user to firebase messaging topic for push notifications
  Future<void> updateUserDeviceToken() async {
    /// Get device token
    final userDeviceToken = await _fcm.getToken();

    /// Subscribe user to receive push notifications
    await _fcm.subscribeToTopic(NOTIFY_USERS);

    /// Update user device token
    /// Check token result
    if (userDeviceToken != null) {
      await updateUserData(userId: getFirebaseUser!.uid, data: {
        USER_DEVICE_TOKEN: userDeviceToken,
      }).then((_) {
        debugPrint("updateUserDeviceToken() -> success");
      });
    }
  }

  /// Set user VIP true
  void setUserVip() {
    userIsVip = true;
    notifyListeners();
  }

  /// Set Active VIP Subscription ID
  void setActiveVipId(String subscriptionId) {
    activeVipId = subscriptionId;
    notifyListeners();
  }

  /// Calculate user current age
  int calculateUserAge(DateTime birthDate) {
    DateTime currentDate = DateTime.now();
    // Get user age based in years
    int age = currentDate.year - birthDate.year;
    // Get current month
    int currentMonth = currentDate.month;
    // Get user birth month
    int birthMonth = birthDate.month;

    if (birthMonth > currentMonth) {
      // Decrement user age
      age--;
    } else if (currentMonth == birthMonth) {
      // Get current day
      int currentDay = currentDate.day;
      // Get user birth day
      int birthDay = birthDate.day;
      // Check days
      if (birthDay > currentDay) {
        // Decrement user age
        age--;
      }
    }
    return age;
  }

  /// Authenticate User Account
  Future<void> authUserAccount({
    // Callback functions for route
    required VoidCallback homeScreen,
    required VoidCallback signUpScreen,
    required VoidCallback updateLocationScreen,
    // Optional functions called on app start
    VoidCallback? signInScreen,
    VoidCallback? blockedScreen,
  }) async {
    /// Check user auth
    if (getFirebaseUser != null) {
      /// Get current user in database
      await getUser(getFirebaseUser!.uid).then((userDoc) {
        /// Check user account in database
        /// if exists check status and take action
        if (userDoc.exists) {
          // Check location data:
          // Get User's latitude & longitude
          final GeoPoint userGeoPoint = userDoc[USER_GEO_POINT]['geopoint'];
          final double latitude = userGeoPoint.latitude;
          final double longitude = userGeoPoint.longitude;

          /// Check User Account Status
          if (userDoc[USER_STATUS] == 'blocked') {
            // Go to blocked user account screen
            blockedScreen!();
          } else {

            // Update UserModel for current user
            updateUserObject(userDoc.data()!);

            // Update user device token and subscribe to fcm topic
            updateUserDeviceToken();

            // Check location data
            if (latitude == 0.0 && longitude == 0.0) {
              // Show Update your current location message
              updateLocationScreen();
              return;
            }

            // Go to home screen
            homeScreen();
          }
          // Debug
          debugPrint("firebaseUser exists");
        } else {
          // Debug
          debugPrint("firebaseUser does not exists");
          // Go to Sign Up Screen
          signUpScreen();
        }
      });
    } else {
      debugPrint("firebaseUser not logged in");
      signInScreen!();
    }
  }

  /// Verify phone number and handle phone auth
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    // Callback functions
    required Function() checkUserAccount,
    required Function(String verificationId) codeSent,
    required Function(String errorType, String? msg) onError,
  }) async {
    // Debug phone number
    debugPrint('phoneNumber is: $phoneNumber');

    /// **** CallBack functions **** ///

    // Auto validate SMS code and return AuthResult to get user.
    verificationComplete(fire_auth.AuthCredential authCredential) async {
      // signIn with auto retrieved sms code
      await _firebaseAuth
          .signInWithCredential(authCredential)
          .then((fire_auth.UserCredential userCredential) {
        /// Auth user account
        checkUserAccount();
      });
      // Debug
      debugPrint('verificationComplete() -> signedIn');
    }

    smsCodeSent(String verificationId, List<int?> code) async {
      // Debug
      debugPrint('smsCodeSent() -> verificationId: $verificationId');
      // Callback function
      codeSent(verificationId);
    }

    verificationFailed(fire_auth.FirebaseAuthException authException) async {
      // CallBack function
      onError('invalid_number', authException.message);
      // debugPrint error on console
      debugPrint(
          'verificationFailed() -> error: ${authException.message.toString()}');
    }

    codeAutoRetrievalTimeout(String verificationId) async {
      // CallBack function
      onError('timeout', null);
      // Debug
      debugPrint(
          'codeAutoRetrievalTimeout() -> verificationId: $verificationId');
    }

    await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (authCredential) =>
            verificationComplete(authCredential),
        verificationFailed: (authException) =>
            verificationFailed(authException),
        codeAutoRetrievalTimeout: (verificationId) =>
            codeAutoRetrievalTimeout(verificationId),
        // called when the SMS code is sent
        codeSent: (verificationId, [code]) =>
            smsCodeSent(verificationId, [code]));
  }

  /// Sign In with OPT sent to user device
  Future<void> signInWithOTP(
      {required String verificationId,
      required String otp,
      // Callback functions
      required Function() checkUserAccount,
      required VoidCallback onError}) async {
    /// Get AuthCredential
    final fire_auth.AuthCredential credential =
        fire_auth.PhoneAuthProvider.credential(
            verificationId: verificationId, smsCode: otp);

    /// Try to sign in with provided credential
    await _firebaseAuth
        .signInWithCredential(credential)
        .then((fire_auth.UserCredential userCredential) {
      /// Auth user account
      checkUserAccount();
    }).catchError((error) {
      // Callback function
      onError();
    });
  }

  ///
  /// Create the User Account method
  ///
  Future<void> signUp({
    required File userPhotoFile,
    required String userFullName,
    required String userGender,
    required int userBirthDay,
    required int userBirthMonth,
    required int userBirthYear,
    required String userSchool,
    required String userJobTitle,
    required String userBio,
    // Callback functions
    required VoidCallback onSuccess,
    required Function(String) onFail,
  }) async {
    // Notify
    isLoading = true;
    notifyListeners();

    /// Set Geolocation point
    final GeoFirePoint geoPoint = _geo.point(latitude: 0.0, longitude: 0.0);

    /// Get user device token for push notifications
    final userDeviceToken = await _fcm.getToken();

    /// Upload user profile image
    final String imageProfileUrl = await uploadFile(
        file: userPhotoFile,
        path: 'uploads/users/profiles',
        userId: getFirebaseUser!.uid);

    /// Save user information in database
    await _firestore
        .collection(C_USERS)
        .doc(getFirebaseUser!.uid)
        .set(<String, dynamic>{
      USER_ID: getFirebaseUser!.uid,
      USER_PROFILE_PHOTO: imageProfileUrl,
      USER_FULLNAME: userFullName,
      USER_GENDER: userGender,
      USER_BIRTH_DAY: userBirthDay,
      USER_BIRTH_MONTH: userBirthMonth,
      USER_BIRTH_YEAR: userBirthYear,
      USER_SCHOOL: userSchool,
      USER_JOB_TITLE: userJobTitle,
      USER_BIO: userBio,
      USER_PHONE_NUMBER: getFirebaseUser!.phoneNumber ?? '',
      USER_EMAIL: getFirebaseUser!.email ?? '',
      USER_STATUS: 'active',
      USER_LEVEL: 'user',
      // User location info
      USER_GEO_POINT: geoPoint.data,
      USER_COUNTRY: '',
      USER_LOCALITY: '',
      USER_Hide_Profile_Time: '',
      // End
      USER_LAST_LOGIN: FieldValue.serverTimestamp(),
      USER_REG_DATE: FieldValue.serverTimestamp(),
      USER_DEVICE_TOKEN: userDeviceToken,
      // Set User default settings
      USER_SETTINGS: {
        USER_MIN_AGE: 18, // int
        USER_MAX_AGE: 100, // int
        // USER_SHOW_ME: '',
        USER_Hide_Time :"",
        USER_MAX_DISTANCE: AppModel().appInfo.freeAccountMaxDistance, // double
      },
    }).then((_) async {
      /// Get current user in database
      final DocumentSnapshot<Map<String, dynamic>> userDoc =
          await getUser(getFirebaseUser!.uid);

      /// Update UserModel for current user
      updateUserObject(userDoc.data()!);

      /// Update loading status
      isLoading = false;
      notifyListeners();
      debugPrint('signUp() -> success');

      /// Callback function
      onSuccess();
    }).catchError((onError) {
      isLoading = false;
      notifyListeners();
      debugPrint('signUp() -> error');
      // Callback function
      onError(onError);
    });
  }

  /// Update current user profile
  Future<void> updateProfile({
    required String userSchool,
    required String userJobTitle,
    required String userBio,
    // Callback functions
    required VoidCallback onSuccess,
    required Function(String) onFail,
  }) async {
    /// Update user profile
    updateUserData(userId: user.userId, data: {
      USER_SCHOOL: userSchool,
      USER_JOB_TITLE: userJobTitle,
      USER_BIO: userBio,
    }).then((_) {
      isLoading = false;
      notifyListeners();
      debugPrint('updateProfile() -> success');
      // Callback function
      onSuccess();
    }).catchError((onError) {
      isLoading = false;
      notifyListeners();
      debugPrint('updateProfile() -> error');
      // Callback function
      onError(onError);
    });
  }

  /// Flag User profile
  Future<void> flagUserProfile(
      {required String flaggedUserId, required String reason}) async {
    await _firestore.collection(C_FLAGGED_USERS).doc().set({
      FLAGGED_USER_ID: flaggedUserId,
      FLAG_REASON: reason,
      FLAGGED_BY_USER_ID: user.userId,
      TIMESTAMP: FieldValue.serverTimestamp()
    });
    // Update flagged profile status
    await updateUserData(userId: flaggedUserId, data: {USER_STATUS: 'flagged'});
  }

  /// Update User location info
  Future<void> updateUserLocation({
    required bool isPassport,
    LocationResult? locationResult,
    // Callback functions
    required VoidCallback onSuccess,
    required VoidCallback onFail,
  }) async {
    // Variables
    String country = '';
    String locality = '';

    GeoFirePoint geoPoint;

    // Check the passport param
    if (!isPassport) {
      /// Update user location: Country, City and Geo Data
      ///
      /// Get user current location using GPS
      final Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      /// Get User location from formatted address
      final Placemark place = await _appHelper.getUserAddress(
          position.latitude, position.longitude);
      // Set values
      country = place.country ?? '';
      // Check
      if (place.locality != '') {
        locality = place.locality.toString();
      } else {
        locality = place.subAdministrativeArea.toString();
      }

      /// Set Geolocation point
      geoPoint = _geo.point(
          latitude: position.latitude, longitude: position.longitude);
    } else {
      // Get location data from passort feature
      //country = locationResult.country.name ?? '';
      // Check country result
      if (locationResult!.country!.name != null) {
        country = locationResult.country!.name.toString();
      }

      // Check locality result
      if (locationResult.city!.name != null) {
        locality = locationResult.city!.name.toString();
      } else {
        locality = locationResult.locality.toString();
      }

      // Get Latitute & Longitude from passort feature
      LatLng latAndlong = locationResult.latLng!;

      // Get information from passport feature
      geoPoint = _geo.point(
          latitude: latAndlong.latitude, longitude: latAndlong.longitude);
    }

    /// Check place result before updating user info
    if (country != '') {
      // Update user location
      await UserModel().updateUserData(userId: UserModel().user.userId, data: {
        USER_GEO_POINT: geoPoint.data,
        USER_COUNTRY: country,
        USER_LOCALITY: locality
      });

      // Show success message
      onSuccess();
      debugPrint('updateUserLocation() -> success');
    } else {
      // Show error message
      onSuccess();
      debugPrint('updateUserLocation() -> success');
    }
  }

  /// Validate the user's maximum distance to
  /// decrement it to the free distance radius
  /// if user canceled the VIP subscription and
  /// avoids the error in the Slider located at lib/settings_screen.dart
  Future<void> checkUserMaxDistance() async {
    //
    // Get current user max distance
    final double userMaxDistance =
        user.userSettings![USER_MAX_DISTANCE].toDouble();

    // Hold the allowed max distance
    double allowedMaxDistance = 0.0;

    // Check VIP Account
    if (UserModel().userIsVip) {
      // Get allowed VIP distance
      allowedMaxDistance = AppModel().appInfo.vipAccountMaxDistance;
      // Debug
      debugPrint('checkUserMaxDistance() -> User is VIP Account.');
    } else {
      // Get allowed FREE distance
      allowedMaxDistance = AppModel().appInfo.freeAccountMaxDistance;
      // Debug
      debugPrint('checkUserMaxDistance() -> User is FREE Account.');
    }

    // *** Validate the allowed max distance *** //
    if (userMaxDistance > allowedMaxDistance) {
      // Give user free distance again
      await updateUserData(
          userId: user.userId,
          data: {'$USER_SETTINGS.$USER_MAX_DISTANCE': allowedMaxDistance});
      debugPrint('checkUserMaxDistance() -> updated successfully');
    } else {
      debugPrint("checkUserMaxDistance() -> it'is valid");
    }
  }

  /// Upload file to firesrore
  Future<String> uploadFile({
    required File file,
    required String path,
    required String userId,
  }) async {
    // Image name
    String imageName =
        userId + DateTime.now().millisecondsSinceEpoch.toString();
    // Upload file
    final UploadTask uploadTask = _storageRef
        .ref()
        .child(path + '/' + userId + '/' + imageName)
        .putFile(file);
    final TaskSnapshot snapshot = await uploadTask;
    String url = await snapshot.ref.getDownloadURL();
    // return file link
    return url;
  }

  /// Add / Update profile image and gallery
  Future<void> updateProfileImage(
      {required File imageFile,
      String? oldImageUrl,
      required String path,
      int? index}) async {
    // Variables
    String uploadPath;

    /// Check upload path
    if (path == 'profile') {
      uploadPath = 'uploads/users/profiles';
    } else {
      uploadPath = 'uploads/users/gallery';
    }

    /// Delete previous uploaded image if not nul
    if (oldImageUrl != null) {
      await FirebaseStorage.instance.refFromURL(oldImageUrl).delete();
    }

    /// Upload new image
    final imageLink = await uploadFile(
        file: imageFile, path: uploadPath, userId: user.userId);

    if (path == 'profile') {
      /// Update profile image link
      await updateUserData(
          userId: user.userId, data: {USER_PROFILE_PHOTO: imageLink});
    } else {
      /// Update gallery image
      await updateUserData(
          userId: user.userId, data: {'$USER_GALLERY.image_$index': imageLink});
    }
  }

  /// Delete image from user gallery
  Future<void> deleteGalleryImage(
      {required String imageUrl, required int index}) async {
    /// Delete image
    await FirebaseStorage.instance.refFromURL(imageUrl).delete();

    /// Update user gallery
    await updateUserData(
        userId: user.userId,
        data: {'$USER_GALLERY.image_$index': FieldValue.delete()});
  }

  /// Get user profile images
  List<String> getUserProfileImages(User user) {
    // Get profile photo
    List<String> images = [user.userProfilePhoto];
    // loop user profile gallery images
    if (user.userGallery != null) {
      user.userGallery!.forEach((key, imgUrl) {
        images.add(imgUrl);
      });
    }
    debugPrint('Profile Gallery list: ${images.length}');
    return images;
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
      await _firebaseAuth.signOut();
      notifyListeners();
      debugPrint("signOut() -> success");
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  // Filter the User Gender
  Query<Map<String, dynamic>> filterUserGender(
      Query<Map<String, dynamic>> query) {
    // Get the opposite gender
    final String oppositeGender = user.userGender == "Male" ? "Female" : "Male";

    /// Get user settings
    final Map<String, dynamic>? settings = user.userSettings;
    // Debug
    // debugPrint('userSettings: $settings');

    // Handle Show Me option
    if (settings != null) {
      // Check show me option
      if (settings[USER_SHOW_ME] != null) {
        // Control show me option
        switch (settings[USER_SHOW_ME]) {
          case 'men':
            query = query.where(USER_GENDER, isEqualTo: 'Male');
            break;
          case 'women':
            query = query.where(USER_GENDER, isEqualTo: 'Female');
            break;
          case 'everyone':
            // Do nothing - app will get everyone
            break;
        }
      } else {
        query = query.where(USER_GENDER, isEqualTo: oppositeGender);
      }
    }
    // Returns the result query
    return query;
  }
}
