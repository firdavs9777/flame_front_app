import 'package:uuid/uuid.dart';
import '../models/models.dart';

class MockDataService {
  static const _uuid = Uuid();

  static final User currentUser = User(
    id: 'current_user',
    name: 'You',
    age: 28,
    bio: 'Looking for meaningful connections. Love hiking, coffee, and good conversations.',
    photos: [
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
    ],
    location: 'San Francisco, CA',
    distance: 0,
    interests: ['Hiking', 'Coffee', 'Photography', 'Travel', 'Music'],
    gender: Gender.male,
    lookingFor: Gender.female,
    minAgePreference: 23,
    maxAgePreference: 35,
    maxDistancePreference: 25,
    lastActive: DateTime.now(),
    isOnline: true,
  );

  static final List<User> potentialMatches = [
    User(
      id: _uuid.v4(),
      name: 'Emma',
      age: 26,
      bio: 'Adventure seeker 🌍 Coffee enthusiast ☕ Dog mom 🐕',
      photos: [
        'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400',
        'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=400',
        'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=400',
      ],
      location: 'San Francisco, CA',
      distance: 3,
      interests: ['Travel', 'Coffee', 'Dogs', 'Yoga', 'Photography'],
      gender: Gender.female,
      lookingFor: Gender.male,
      lastActive: DateTime.now().subtract(const Duration(minutes: 5)),
      isOnline: true,
    ),
    User(
      id: _uuid.v4(),
      name: 'Sofia',
      age: 24,
      bio: 'Artist by day, foodie by night. Looking for someone to explore new restaurants with!',
      photos: [
        'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400',
        'https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e?w=400',
      ],
      location: 'Oakland, CA',
      distance: 8,
      interests: ['Art', 'Food', 'Wine', 'Movies', 'Dancing'],
      gender: Gender.female,
      lookingFor: Gender.male,
      lastActive: DateTime.now().subtract(const Duration(hours: 2)),
      isOnline: false,
    ),
    User(
      id: _uuid.v4(),
      name: 'Olivia',
      age: 27,
      bio: 'Tech nerd who loves board games and hiking. Let\'s grab coffee! ☕',
      photos: [
        'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?w=400',
        'https://images.unsplash.com/photo-1502823403499-6ccfcf4fb453?w=400',
        'https://images.unsplash.com/photo-1464863979621-258859e62245?w=400',
      ],
      location: 'San Jose, CA',
      distance: 15,
      interests: ['Technology', 'Board Games', 'Hiking', 'Coffee', 'Reading'],
      gender: Gender.female,
      lookingFor: Gender.male,
      lastActive: DateTime.now().subtract(const Duration(minutes: 30)),
      isOnline: true,
    ),
    User(
      id: _uuid.v4(),
      name: 'Isabella',
      age: 25,
      bio: 'Fitness enthusiast 💪 Beach lover 🏖️ Always up for an adventure!',
      photos: [
        'https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?w=400',
        'https://images.unsplash.com/photo-1515023115689-589c33041d3c?w=400',
      ],
      location: 'Palo Alto, CA',
      distance: 12,
      interests: ['Fitness', 'Beach', 'Surfing', 'Cooking', 'Meditation'],
      gender: Gender.female,
      lookingFor: Gender.male,
      lastActive: DateTime.now().subtract(const Duration(hours: 1)),
      isOnline: false,
    ),
    User(
      id: _uuid.v4(),
      name: 'Mia',
      age: 29,
      bio: 'Bookworm 📚 Wine connoisseur 🍷 Looking for deep conversations.',
      photos: [
        'https://images.unsplash.com/photo-1524250502761-1ac6f2e30d43?w=400',
        'https://images.unsplash.com/photo-1519699047748-de8e457a634e?w=400',
        'https://images.unsplash.com/photo-1496440737103-cd596325d314?w=400',
      ],
      location: 'Berkeley, CA',
      distance: 10,
      interests: ['Reading', 'Wine', 'Philosophy', 'Jazz', 'Cooking'],
      gender: Gender.female,
      lookingFor: Gender.male,
      lastActive: DateTime.now().subtract(const Duration(days: 1)),
      isOnline: false,
    ),
    User(
      id: _uuid.v4(),
      name: 'Ava',
      age: 23,
      bio: 'Music is my therapy 🎵 Concert buddy wanted! Also love hiking and brunch.',
      photos: [
        'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=400',
        'https://images.unsplash.com/photo-1489424731084-a5d8b219a5bb?w=400',
      ],
      location: 'San Francisco, CA',
      distance: 5,
      interests: ['Music', 'Concerts', 'Hiking', 'Brunch', 'Photography'],
      gender: Gender.female,
      lookingFor: Gender.male,
      lastActive: DateTime.now().subtract(const Duration(minutes: 15)),
      isOnline: true,
    ),
    User(
      id: _uuid.v4(),
      name: 'Charlotte',
      age: 28,
      bio: 'Veterinarian 🐾 Animal lover. Looking for someone kind and genuine.',
      photos: [
        'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400',
        'https://images.unsplash.com/photo-1502767089025-6572583495f9?w=400',
        'https://images.unsplash.com/photo-1485893086445-ed75865251e0?w=400',
      ],
      location: 'Mountain View, CA',
      distance: 18,
      interests: ['Animals', 'Nature', 'Volunteering', 'Cooking', 'Movies'],
      gender: Gender.female,
      lookingFor: Gender.male,
      lastActive: DateTime.now().subtract(const Duration(hours: 3)),
      isOnline: false,
    ),
    User(
      id: _uuid.v4(),
      name: 'Luna',
      age: 26,
      bio: 'Startup founder 🚀 Always learning. Let\'s talk about ideas over tacos!',
      photos: [
        'https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?w=400',
        'https://images.unsplash.com/photo-1484399172022-72a90b12e3c1?w=400',
      ],
      location: 'San Francisco, CA',
      distance: 2,
      interests: ['Startups', 'Technology', 'Tacos', 'Running', 'Podcasts'],
      gender: Gender.female,
      lookingFor: Gender.male,
      lastActive: DateTime.now(),
      isOnline: true,
    ),
  ];

  static List<Match> getMatches() {
    return [
      Match(
        id: _uuid.v4(),
        user: potentialMatches[0],
        matchedAt: DateTime.now().subtract(const Duration(hours: 2)),
        isNew: true,
      ),
      Match(
        id: _uuid.v4(),
        user: potentialMatches[2],
        matchedAt: DateTime.now().subtract(const Duration(days: 1)),
        isNew: false,
      ),
      Match(
        id: _uuid.v4(),
        user: potentialMatches[5],
        matchedAt: DateTime.now().subtract(const Duration(days: 3)),
        isNew: false,
      ),
    ];
  }

  static List<Conversation> getConversations() {
    final matches = getMatches();
    return [
      Conversation(
        id: _uuid.v4(),
        otherUser: matches[0].user,
        messages: [
          Message(
            id: _uuid.v4(),
            senderId: matches[0].user.id,
            receiverId: currentUser.id,
            content: 'Hey! I noticed we both love hiking. Any favorite trails?',
            timestamp: DateTime.now().subtract(const Duration(hours: 1)),
            status: MessageStatus.read,
          ),
          Message(
            id: _uuid.v4(),
            senderId: currentUser.id,
            receiverId: matches[0].user.id,
            content: 'Hey! Yes! I love the Dipsea Trail in Mill Valley. Have you been?',
            timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
            status: MessageStatus.delivered,
          ),
          Message(
            id: _uuid.v4(),
            senderId: matches[0].user.id,
            receiverId: currentUser.id,
            content: 'Not yet but it\'s on my list! We should go sometime 😊',
            timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
            status: MessageStatus.read,
          ),
        ],
        lastMessageAt: DateTime.now().subtract(const Duration(minutes: 30)),
        unreadCount: 1,
      ),
      Conversation(
        id: _uuid.v4(),
        otherUser: matches[1].user,
        messages: [
          Message(
            id: _uuid.v4(),
            senderId: currentUser.id,
            receiverId: matches[1].user.id,
            content: 'Hey Olivia! What kind of board games do you play?',
            timestamp: DateTime.now().subtract(const Duration(days: 1)),
            status: MessageStatus.delivered,
          ),
        ],
        lastMessageAt: DateTime.now().subtract(const Duration(days: 1)),
        unreadCount: 0,
      ),
    ];
  }
}
