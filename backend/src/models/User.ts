import { Schema, model, Types, Document } from "mongoose";

export type UserRole = "PARENT" | "CHILD";

export interface IUser extends Document {
  _id: Types.ObjectId;
  name: string;
  email: string; // used as login identifier for both roles (child can use a username-style email)
  passwordHash: string;
  role: UserRole;
  // Only set for CHILD users:
  parentId?: Types.ObjectId;
  refreshTokenVersion: number; // bump to invalidate all existing refresh tokens
  createdAt: Date;
  updatedAt: Date;
}

const userSchema = new Schema<IUser>(
  {
    name: { type: String, required: true, trim: true, maxlength: 100 },
    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true,
      index: true,
    },
    passwordHash: { type: String, required: true },
    role: { type: String, enum: ["PARENT", "CHILD"], required: true },
    parentId: { type: Schema.Types.ObjectId, ref: "User", default: null },
    refreshTokenVersion: { type: Number, default: 0 },
  },
  { timestamps: true }
);

export const User = model<IUser>("User", userSchema);
