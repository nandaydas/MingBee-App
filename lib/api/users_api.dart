import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dating_app/api/blocked_users_api.dart';
import 'package:dating_app/constants/constants.dart';
import 'package:dating_app/models/user_model.dart';
import 'package:dating_app/plugins/geoflutterfire/geoflutterfire.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class UsersApi {
  /// Get firestore instance
  ///
  final _firestore = FirebaseFirestore.instance;

  late DateTime second;
  /// Get all users
  ///
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> getUsers({
    required List<DocumentSnapshot<Map<String, dynamic>>> dislikedUsers,
  }) async {
    /// Build Users query
    Query<Map<String, dynamic>> usersQuery = _firestore
        .collection(C_USERS)
        .where(USER_STATUS, isEqualTo: 'active')
        .where(USER_LEVEL, isEqualTo: 'user');

    // Filter the User Gender
    usersQuery = UserModel().filterUserGender(usersQuery);

    // Instance of Geoflutterfire
    final Geoflutterfire geo = Geoflutterfire();

    /// Get user settings
    final Map<String, dynamic>? settings = UserModel().user.userSettings;

    // // Get user geo center
    final GeoFirePoint center = geo.point(
        latitude: UserModel().user.userGeoPoint.latitude,
        longitude: UserModel().user.userGeoPoint.longitude);

    final allUsers = await geo
        .collection(collectionRef: usersQuery)
        .within(
            center: center,
            radius: settings![USER_MAX_DISTANCE].toDouble(),
            field: USER_GEO_POINT,
            strictMode: true)
        .first;


    DateTime firstTime = DateTime.now();
print("firstTime=> ${firstTime}");
    // Remove the current user profile - If choosed to see everyone
    if (allUsers.isNotEmpty) {
      allUsers.removeWhere((userDoc) => userDoc[USER_ID] == UserModel().user.userId);
      for(int i=0;i<allUsers.length;i++){

        if(allUsers[i].data()?[USER_Hide_Profile_Time] != ""){
          String Date = allUsers[i].data()?[USER_Hide_Profile_Time];
          second = DateTime.parse(Date);

          // Comparing times
          if (second.isBefore(firstTime)) {
            print('before=> $firstTime is before $second');
          } else if (second.isAfter(firstTime)) {
            print('after=> $firstTime is after $second');
            print("USER_ID=> ${allUsers[i].data()?[USER_ID]}");
            allUsers.removeWhere((element) => element[USER_ID] == allUsers[i].data()?[USER_ID]);
          } else {
            print('$firstTime is equal to $second');
          }
        }

      }
    }


    /// Remove Disliked Users in list
    if (dislikedUsers.isNotEmpty) {
      for (var dislikedUser in dislikedUsers) {
        allUsers.removeWhere(
            (userDoc) => userDoc[USER_ID] == dislikedUser[DISLIKED_USER_ID]);
      }
    }

    // Get Liked Profiles
    final List<DocumentSnapshot<Map<String, dynamic>>> likedProfiles =
        (await _firestore
                .collection(C_LIKES)
                .where(LIKED_BY_USER_ID, isEqualTo: UserModel().user.userId)
                .get())
            .docs;

    // Remove Liked Profiles
    if (likedProfiles.isNotEmpty) {
      for (var likedUser in likedProfiles) {
        allUsers.removeWhere(
            (userDoc) => userDoc[USER_ID] == likedUser[LIKED_USER_ID]);
      }
    }

    // NEW feature - Remove Blocked Profiles from the list
    await BlockedUsersApi().removeBlockedUsers(allUsers).then((_) {
      debugPrint('removeBlockedUsers() -> success');
    }).catchError((e) {
      debugPrint('removeBlockedUsers() -> error: $e');
    });

    /// Sort by newest
    allUsers.sort((a, b) {
      final DateTime userRegDateA = a[USER_REG_DATE].toDate();
      final DateTime userRegDateB = b[USER_REG_DATE].toDate();
      return userRegDateA.compareTo(userRegDateB);
    });

    final int minAge = settings[USER_MIN_AGE];
    final int maxAge = settings[USER_MAX_AGE];

    // Filter Profile Ages
    return allUsers.where((DocumentSnapshot<Map<String, dynamic>> user) {
      // Get User Birthday
      final DateTime userBirthday = DateTime(
          user[USER_BIRTH_YEAR], user[USER_BIRTH_MONTH], user[USER_BIRTH_DAY]);

      /// Get user profile age to filter
      final int profileAge = UserModel().calculateUserAge(userBirthday);
      // Return result
      return profileAge >= minAge && profileAge <= maxAge;
    }).toList();
  }
  void method() {
    DateTime firstTime = DateTime.now();
    print("firstTime=> $firstTime");
    // Comparing times
    if (second.isBefore(firstTime)) {
      print('before=> $firstTime is before $second');
    } else if (second.isAfter(firstTime)) {
      print('after=> $firstTime is after $second');
    } else {
      print('$firstTime is equal to $second');
    }
  }
}
