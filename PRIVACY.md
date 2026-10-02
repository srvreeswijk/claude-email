# Privacy Policy

Last updated: 2 October 2026

This policy covers the "n8n-mail" application: a personal, self-hosted n8n automation that reads payslip emails in a single Gmail account. The app is used only by its developer, on the developer's own mailbox. It is not offered to anyone else.

## What Google user data the app accesses

Through the Gmail API, the app:

- searches the mailbox for messages from one specific sender (`noreply@p-direkt.minbzk.nl`),
- reads those messages and their PDF attachments,
- reads the list of Gmail labels,
- adds a label to those messages and marks them as read.

It does not send, delete, move or archive email, and it does not read other messages than those matching the search.

## How the data is used

The text of the PDF attachment is used to extract a few amounts and send a short summary as a notification to the developer's own phone. Nothing else is done with it.

## Where the data goes

- **The developer's own computer.** n8n runs locally. Email content and processing logs are stored only there, and processing logs are deleted automatically after 7 days.
- **Anthropic API.** The PDF text, with account and personnel numbers removed, is sent to the Anthropic API to extract the amounts. Anthropic processes it under its commercial terms and does not use API data to train its models.
- **Telegram.** The short summary is sent to the developer's own Telegram chat.

Google user data is not sold, not used for advertising, and not shared with anyone else.

## Limited Use

The app's use and transfer of information received from Google APIs adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements.

## Revoking access

Access can be revoked at any time at https://myaccount.google.com/permissions. Removing the n8n credential or the `n8n_data` volume deletes the stored token and logs.

## Contact

Questions about this policy can be sent to the developer at the email address shown on the app's Google consent screen.
