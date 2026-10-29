package com.example.childapp.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.childapp.R
import com.example.childapp.ui.theme.AppTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginScreen(
    loading: Boolean,
    error: String?,
    onLogin: (username: String, password: String) -> Unit
) {
    val context = LocalContext.current
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var passwordVisible by remember { mutableStateOf(false) }
    var showInfoDialog by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val passwordVisualTransformation = remember { PasswordVisualTransformation() }

    val logoBitmap = remember(context) {
        try {
            context.assets.open("images/logo.png").use { inputStream ->
                BitmapFactory.decodeStream(inputStream)?.asImageBitmap()
            }
        } catch (_: Exception) {
            null
        }
    }

    val textFieldColors = OutlinedTextFieldDefaults.colors(
        focusedContainerColor = AppTheme.palette.card,
        unfocusedContainerColor = AppTheme.palette.card,
        disabledContainerColor = AppTheme.palette.card,
        errorContainerColor = AppTheme.palette.card,
        focusedBorderColor = AppTheme.palette.ring,
        unfocusedBorderColor = AppTheme.palette.border,
        errorBorderColor = MaterialTheme.colorScheme.error,
        focusedLabelColor = AppTheme.palette.foreground.copy(alpha = 0.8f),
        unfocusedLabelColor = AppTheme.palette.foreground.copy(alpha = 0.8f),
        errorLabelColor = MaterialTheme.colorScheme.error,
        focusedTextColor = AppTheme.palette.foreground,
        unfocusedTextColor = AppTheme.palette.foreground,
        cursorColor = AppTheme.palette.primary,
        focusedTrailingIconColor = AppTheme.palette.primary,
        unfocusedTrailingIconColor = AppTheme.palette.primary
    )

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
            contentAlignment = Alignment.Center
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Box(
                    modifier = Modifier.fillMaxWidth(),
                    contentAlignment = Alignment.Center
                ) {
                    if (logoBitmap != null) {
                        Image(
                            bitmap = logoBitmap,
                            contentDescription = "Seftly Logo",
                            modifier = Modifier.size(110.dp),
                            contentScale = ContentScale.Fit
                        )
                    } else {
                        Image(
                            painter = painterResource(id = R.drawable.logo),
                            contentDescription = "Seftly Logo",
                            modifier = Modifier.size(110.dp),
                            contentScale = ContentScale.Fit
                        )
                    }
                }

                Spacer(modifier = Modifier.height(20.dp))

                Text(
                    text = "Seftly Child login",
                    style = MaterialTheme.typography.headlineMedium,
                    color = MaterialTheme.colorScheme.onBackground,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(24.dp))

                OutlinedTextField(
                    value = username,
                    onValueChange = { username = it },
                    label = { Text("Email") },
                    singleLine = true,
                    shape = RoundedCornerShape(AppTheme.palette.radius),
                    colors = textFieldColors,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Email,
                        imeAction = ImeAction.Next
                    ),
                    keyboardActions = KeyboardActions(
                        onNext = { focusManager.moveFocus(FocusDirection.Down) }
                    ),
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(12.dp))

                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("Password") },
                    singleLine = true,
                    shape = RoundedCornerShape(AppTheme.palette.radius),
                    colors = textFieldColors,
                    visualTransformation = if (passwordVisible) VisualTransformation.None else passwordVisualTransformation,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Password,
                        imeAction = ImeAction.Done
                    ),
                    keyboardActions = KeyboardActions(
                        onDone = {
                            focusManager.clearFocus()
                            if (!loading && username.isNotBlank() && password.isNotBlank()) {
                                onLogin(username.trim(), password)
                            }
                        }
                    ),
                    trailingIcon = {
                        IconButton(onClick = { passwordVisible = !passwordVisible }) {
                            Icon(
                                imageVector = if (passwordVisible) Icons.Filled.Visibility else Icons.Filled.VisibilityOff,
                                contentDescription = if (passwordVisible) "Hide password" else "Show password"
                            )
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(20.dp))

                if (error != null) {
                    Text(
                        text = error,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 12.dp)
                    )
                }

                Button(
                    onClick = {
                        focusManager.clearFocus()
                        onLogin(username.trim(), password)
                    },
                    enabled = !loading && username.isNotBlank() && password.isNotBlank(),
                    shape = RoundedCornerShape(AppTheme.palette.radius),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = AppTheme.palette.primary,
                        contentColor = AppTheme.palette.primaryForeground,
                        disabledContainerColor = AppTheme.palette.primary.copy(alpha = 0.5f),
                        disabledContentColor = AppTheme.palette.primaryForeground.copy(alpha = 0.7f)
                    ),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp)
                ) {
                    if (loading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = AppTheme.palette.primaryForeground
                        )
                    } else {
                        Text(
                            text = "Log In",
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontWeight = FontWeight.SemiBold
                            )
                        )
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                TextButton(
                    onClick = { showInfoDialog = true },
                    shape = RoundedCornerShape(AppTheme.palette.radius)
                ) {
                    Text(
                        text = "Don't have an account? Register",
                        color = AppTheme.palette.primary,
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        }
    }

    if (showInfoDialog) {
        AlertDialog(
            onDismissRequest = { showInfoDialog = false },
            confirmButton = {
                TextButton(onClick = { showInfoDialog = false }) {
                    Text("OK", color = AppTheme.palette.primary)
                }
            },
            title = {
                Text(
                    text = "Child Account Registration",
                    color = AppTheme.palette.popoverForeground,
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                )
            },
            text = {
                Text(
                    text = "Child accounts are created by parents. Please ask your parent to add your account from the Seftly Parent app.",
                    color = AppTheme.palette.popoverForeground,
                    style = MaterialTheme.typography.bodyMedium
                )
            },
            shape = RoundedCornerShape(AppTheme.palette.radius + 4.dp),
            containerColor = AppTheme.palette.popover
        )
    }
}
