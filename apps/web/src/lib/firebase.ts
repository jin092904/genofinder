"use client";

// Firebase 클라이언트 초기화. browser 에서만 사용.
// 모든 NEXT_PUBLIC_* 키는 공개 식별자 — 보안은 Firebase Rules + 백엔드 토큰 검증으로.
import { getApp, getApps, initializeApp, type FirebaseApp } from "firebase/app";
import {
  GoogleAuthProvider,
  getAuth,
  onAuthStateChanged,
  signInWithPopup,
  signOut as fbSignOut,
  type Auth,
  type User as FirebaseUser,
} from "firebase/auth";

const config = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY!,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN!,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID!,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET!,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID!,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID!,
};

let _app: FirebaseApp | null = null;
let _auth: Auth | null = null;

function getOrInit(): { app: FirebaseApp; auth: Auth } {
  if (typeof window === "undefined") {
    throw new Error("firebase client may only be used in the browser");
  }
  if (_app && _auth) return { app: _app, auth: _auth };
  _app = getApps().length ? getApp() : initializeApp(config);
  _auth = getAuth(_app);
  return { app: _app, auth: _auth };
}

export function getFirebaseAuth(): Auth {
  return getOrInit().auth;
}

export async function signInWithGoogle(): Promise<FirebaseUser> {
  const { auth } = getOrInit();
  const provider = new GoogleAuthProvider();
  // 프롬프트 매번 (다른 계정 선택 가능)
  provider.setCustomParameters({ prompt: "select_account" });
  const result = await signInWithPopup(auth, provider);
  return result.user;
}

export async function signOut(): Promise<void> {
  const { auth } = getOrInit();
  await fbSignOut(auth);
}

export {
  onAuthStateChanged,
  type FirebaseUser,
};
