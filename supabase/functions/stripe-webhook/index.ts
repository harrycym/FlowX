import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14?target=deno";

serve(async (req) => {
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");

  if (!stripeKey || !webhookSecret) {
    return new Response(JSON.stringify({ error: "Stripe not configured" }), { status: 500 });
  }

  const stripe = new Stripe(stripeKey, { apiVersion: "2024-06-20" });

  const signature = req.headers.get("stripe-signature");
  if (!signature) {
    return new Response(JSON.stringify({ error: "Missing signature" }), { status: 400 });
  }

  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(body, signature, webhookSecret);
  } catch (err) {
    return new Response(JSON.stringify({ error: `Webhook verification failed: ${(err as Error).message}` }), { status: 400 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  try {
    switch (event.type) {
      case "checkout.session.completed": {
        const session = event.data.object as Stripe.Checkout.Session;
        const userId = session.metadata?.supabase_user_id;
        if (!userId) break;

        const subscriptionId = session.subscription as string;

        // Fetch subscription details from Stripe
        const stripeSub = await stripe.subscriptions.retrieve(subscriptionId);

        await serviceClient
          .from("subscriptions")
          .update({
            plan: "pro",
            word_limit: null, // unlimited
            stripe_subscription_id: subscriptionId,
            stripe_price_id: stripeSub.items.data[0]?.price?.id ?? null,
            status: "active",
            current_period_start: new Date(stripeSub.current_period_start * 1000).toISOString(),
            current_period_end: new Date(stripeSub.current_period_end * 1000).toISOString(),
          })
          .eq("user_id", userId);

        break;
      }

      case "customer.subscription.updated": {
        const sub = event.data.object as Stripe.Subscription;
        const customerId = sub.customer as string;

        const { data: profile } = await serviceClient
          .from("profiles")
          .select("id")
          .eq("stripe_customer_id", customerId)
          .single();

        if (!profile) break;

        const isActive = ["active", "trialing"].includes(sub.status);

        await serviceClient
          .from("subscriptions")
          .update({
            status: sub.status === "active" ? "active" :
                    sub.status === "past_due" ? "past_due" :
                    sub.status === "canceled" ? "canceled" : "active",
            plan: isActive ? "pro" : "free",
            word_limit: isActive ? null : 2000,
            current_period_end: new Date(sub.current_period_end * 1000).toISOString(),
          })
          .eq("user_id", profile.id);

        break;
      }

      case "customer.subscription.deleted": {
        const sub = event.data.object as Stripe.Subscription;
        const customerId = sub.customer as string;

        const { data: profile } = await serviceClient
          .from("profiles")
          .select("id")
          .eq("stripe_customer_id", customerId)
          .single();

        if (!profile) break;

        // Downgrade to free
        await serviceClient
          .from("subscriptions")
          .update({
            plan: "free",
            word_limit: 2000,
            stripe_subscription_id: null,
            stripe_price_id: null,
            status: "canceled",
            current_period_end: null,
          })
          .eq("user_id", profile.id);

        break;
      }

      case "invoice.payment_failed": {
        const invoice = event.data.object as Stripe.Invoice;
        const customerId = invoice.customer as string;

        const { data: profile } = await serviceClient
          .from("profiles")
          .select("id")
          .eq("stripe_customer_id", customerId)
          .single();

        if (!profile) break;

        await serviceClient
          .from("subscriptions")
          .update({ status: "past_due" })
          .eq("user_id", profile.id);

        break;
      }
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 });
  }
});
